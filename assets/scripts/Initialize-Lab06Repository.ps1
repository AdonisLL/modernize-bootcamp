[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SubscriptionId,

    [string]$Repository,

    [string]$DeploymentName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$RequiredReviewer,

    [ValidateNotNullOrEmpty()]
    [string]$DeploymentBranch = 'main'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$buildEnvironment = 'lab06'
$deployEnvironment = 'lab06-deploy'
$requiredOutputs = @(
    'LAB04_BOOTSTRAP_RESOURCE_GROUP',
    'LAB04_PRIMARY_RESOURCE_GROUP',
    'LAB04_SECONDARY_RESOURCE_GROUP',
    'LAB04_GLOBAL_RESOURCE_GROUP',
    'LAB04_PREFIX',
    'LAB04_SUFFIX',
    'LAB06_BUILD_AZURE_CLIENT_ID',
    'LAB06_BUILD_AZURE_PRINCIPAL_ID',
    'LAB06_BUILD_IDENTITY_NAME',
    'LAB06_DEPLOY_AZURE_CLIENT_ID',
    'LAB06_DEPLOY_AZURE_PRINCIPAL_ID',
    'LAB06_DEPLOYMENT_IDENTITY_NAME',
    'LAB06_CONTAINER_REGISTRY_NAME',
    'LAB06_CONTAINER_APP_NAME',
    'LAB06_RUNTIME_IDENTITY_RESOURCE_ID',
    'LAB06_RUNTIME_IDENTITY_CLIENT_ID',
    'FRONT_DOOR_PROFILE_ID'
)

foreach ($command in @('az', 'gh')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command '$command' was not found on PATH."
    }
}

function ConvertFrom-DeploymentOutputs {
    param(
        [Parameter(Mandatory)]
        [object]$Outputs
    )

    $values = @{}
    foreach ($output in $Outputs.PSObject.Properties) {
        $values[$output.Name] = $output.Value.value
    }
    return $values
}

function Test-RequiredOutputs {
    param(
        [Parameter(Mandatory)]
        [object]$Outputs
    )

    foreach ($name in $requiredOutputs) {
        $property = $Outputs.PSObject.Properties[$name]
        if (
            $null -eq $property -or
            [string]::IsNullOrWhiteSpace("$($property.Value.value)")
        ) {
            return $false
        }
    }
    return $true
}

function Get-Lab06Deployment {
    if (-not [string]::IsNullOrWhiteSpace($DeploymentName)) {
        $deployment = az deployment sub show `
            --name $DeploymentName `
            --output json | ConvertFrom-Json
        if ($deployment.properties.provisioningState -ne 'Succeeded') {
            throw "Subscription deployment '$DeploymentName' is not in Succeeded state."
        }
        if (-not (Test-RequiredOutputs -Outputs $deployment.properties.outputs)) {
            throw "Subscription deployment '$DeploymentName' does not contain the complete Lab 06 output contract."
        }
        return $deployment
    }

    $deploymentNames = @(
        az deployment sub list `
            --query "[?properties.provisioningState=='Succeeded'].name" `
            --output tsv
    )
    $matches = @()
    foreach ($name in $deploymentNames) {
        $candidate = az deployment sub show `
            --name $name `
            --output json | ConvertFrom-Json
        if (
            $null -ne $candidate.properties.outputs -and
            (Test-RequiredOutputs -Outputs $candidate.properties.outputs)
        ) {
            $matches += $candidate
        }
    }
    if ($matches.Count -eq 0) {
        throw "No successful subscription deployment contains the complete Lab 06 output contract. Ask the instructor for the preprovisioning deployment name and rerun with -DeploymentName."
    }
    if ($matches.Count -gt 1) {
        $candidateNames = $matches.name -join ', '
        throw "Multiple successful subscription deployments contain Lab 06 outputs: $candidateNames. Rerun with -DeploymentName '<name>'."
    }
    return $matches[0]
}

function Assert-Identity {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$PrincipalId,
        [Parameter(Mandatory)][string]$ResourceGroup
    )

    $identity = az identity show `
        --name $Name `
        --resource-group $ResourceGroup `
        --output json | ConvertFrom-Json
    if (
        $identity.clientId -ne $ClientId -or
        $identity.principalId -ne $PrincipalId
    ) {
        throw "Managed identity '$Name' does not match the client and principal IDs persisted by the Lab 04 deployment."
    }
}

function Assert-RoleAssignment {
    param(
        [Parameter(Mandatory)][string]$PrincipalId,
        [Parameter(Mandatory)][string]$Role,
        [Parameter(Mandatory)][string]$Scope
    )

    $assignments = @(
        az role assignment list `
            --scope $Scope `
            --output json | ConvertFrom-Json
    )
    $matchingAssignments = @(
        $assignments | Where-Object {
            $_.principalId -eq $PrincipalId -and
            $_.roleDefinitionName -eq $Role -and
            $_.scope -eq $Scope
        }
    )
    if ($matchingAssignments.Count -ne 1) {
        throw "Expected exactly one '$Role' assignment for principal '$PrincipalId' at '$Scope', but found $($matchingAssignments.Count). Ask the instructor to repair the preprovisioned Lab 04 RBAC."
    }
}

function Set-FederatedCredential {
    param(
        [Parameter(Mandatory)][string]$IdentityName,
        [Parameter(Mandatory)][string]$EnvironmentName,
        [Parameter(Mandatory)][string]$ResourceGroup
    )

    $credentialName = "github-$EnvironmentName"
    $issuer = 'https://token.actions.githubusercontent.com'
    $subject = "$federatedSubjectPrefix`:environment:$EnvironmentName"
    $audience = 'api://AzureADTokenExchange'
    $existing = @(
        @(
            az identity federated-credential list `
                --identity-name $IdentityName `
                --resource-group $ResourceGroup `
                --output json | ConvertFrom-Json
        ) | Where-Object name -EQ $credentialName
    )

    if ($existing.Count -eq 0) {
        az identity federated-credential create `
            --name $credentialName `
            --identity-name $IdentityName `
            --resource-group $ResourceGroup `
            --issuer $issuer `
            --subject $subject `
            --audiences $audience `
            --output none
    }
    elseif ($existing.Count -eq 1) {
        az identity federated-credential update `
            --name $credentialName `
            --identity-name $IdentityName `
            --resource-group $ResourceGroup `
            --issuer $issuer `
            --subject $subject `
            --audiences $audience `
            --output none
    }
    else {
        throw "Managed identity '$IdentityName' has duplicate '$credentialName' federated credentials."
    }

    $verified = az identity federated-credential show `
        --name $credentialName `
        --identity-name $IdentityName `
        --resource-group $ResourceGroup `
        --output json | ConvertFrom-Json
    if (
        $verified.issuer -ne $issuer -or
        $verified.subject -ne $subject -or
        $verified.audiences.Count -ne 1 -or
        $verified.audiences[0] -ne $audience
    ) {
        throw "Federated credential verification failed for '$IdentityName/$credentialName'."
    }
}

function Set-ProtectedEnvironment {
    param(
        [Parameter(Mandatory)][string]$EnvironmentName,
        [Parameter(Mandatory)][long]$ReviewerId,
        [Parameter(Mandatory)][string]$BranchName
    )

    $encodedEnvironment = [Uri]::EscapeDataString($EnvironmentName)
    $environmentPath = "repos/$Repository/environments/$encodedEnvironment"
    $payload = @{
        wait_timer = 0
        prevent_self_review = $true
        reviewers = @(
            @{
                type = 'User'
                id = $ReviewerId
            }
        )
        deployment_branch_policy = @{
            protected_branches = $false
            custom_branch_policies = $true
        }
    } | ConvertTo-Json -Depth 5 -Compress
    try {
        $payload | gh api --method PUT $environmentPath --input - --silent
    }
    catch {
        throw "Failed to configure GitHub environment '$EnvironmentName' in '$Repository'. Confirm that required reviewers are supported by the repository plan and that the authenticated account has repository ADMIN permission. $($_.Exception.Message)"
    }

    $policiesPath = "$environmentPath/deployment-branch-policies"
    $policies = gh api $policiesPath | ConvertFrom-Json
    foreach ($policy in $policies.branch_policies) {
        if ($policy.name -ne $BranchName) {
            gh api --method DELETE "$policiesPath/$($policy.id)" --silent
        }
    }
    if (-not ($policies.branch_policies | Where-Object name -EQ $BranchName)) {
        gh api --method POST $policiesPath -f "name=$BranchName" --silent
    }

    $verified = gh api $environmentPath | ConvertFrom-Json
    $verifiedPolicies = gh api $policiesPath | ConvertFrom-Json
    $reviewerRule = $verified.protection_rules |
        Where-Object type -EQ 'required_reviewers'
    $reviewerConfigured = $reviewerRule.reviewers |
        Where-Object { $_.reviewer.id -eq $ReviewerId -and $_.type -eq 'User' }
    $branchConfigured = $verifiedPolicies.branch_policies |
        Where-Object name -EQ $BranchName
    if (
        -not $verified.deployment_branch_policy.custom_branch_policies -or
        -not $reviewerRule.prevent_self_review -or
        -not $reviewerConfigured -or
        -not $branchConfigured -or
        $verifiedPolicies.total_count -ne 1
    ) {
        throw "GitHub environment protection verification failed for '$EnvironmentName'."
    }
}

function Set-AndVerifyVariables {
    param(
        [Parameter(Mandatory)][string]$EnvironmentName,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Variables
    )

    foreach ($entry in $Variables.GetEnumerator()) {
        gh variable set $entry.Key `
            --env $EnvironmentName `
            --repo $Repository `
            --body $entry.Value
    }

    $encodedEnvironment = [Uri]::EscapeDataString($EnvironmentName)
    $response = gh api `
        "repos/$Repository/environments/$encodedEnvironment/variables?per_page=100" |
        ConvertFrom-Json
    foreach ($entry in $Variables.GetEnumerator()) {
        $matchingVariable = @(
            $response.variables | Where-Object name -EQ $entry.Key
        )
        if (
            $matchingVariable.Count -ne 1 -or
            $matchingVariable[0].value -ne "$($entry.Value)"
        ) {
            throw "GitHub variable '$($entry.Key)' verification failed in environment '$EnvironmentName'."
        }
    }
}

az account set --subscription $SubscriptionId
$account = az account show --output json | ConvertFrom-Json
if ($account.id -ne $SubscriptionId) {
    throw "Azure CLI selected subscription '$($account.id)' instead of '$SubscriptionId'."
}
$tenantId = [string]$account.tenantId

gh auth status
if (
    -not [string]::IsNullOrWhiteSpace($Repository) -and
    $Repository -notmatch '^[^/]+/[^/]+$'
) {
    throw "Repository must use the 'owner/name' format. Received '$Repository'."
}
$repositoryInfo = if ([string]::IsNullOrWhiteSpace($Repository)) {
    gh repo view --json nameWithOwner,viewerPermission | ConvertFrom-Json
}
else {
    gh repo view $Repository --json nameWithOwner,viewerPermission |
        ConvertFrom-Json
}
$Repository = [string]$repositoryInfo.nameWithOwner
if ($repositoryInfo.viewerPermission -ne 'ADMIN') {
    throw "GitHub environment configuration requires ADMIN permission on '$Repository'. The authenticated account has '$($repositoryInfo.viewerPermission)' permission."
}

$oidcConfiguration = gh api `
    --header 'X-GitHub-Api-Version: 2026-03-10' `
    "repos/$Repository/actions/oidc/customization/sub" |
    ConvertFrom-Json
if (-not $oidcConfiguration.use_default) {
    throw "Repository '$Repository' uses a custom GitHub OIDC subject template. Lab 06 requires the default environment-scoped subject template."
}
$federatedSubjectPrefix = [string]$oidcConfiguration.sub_claim_prefix
if (
    [string]::IsNullOrWhiteSpace($federatedSubjectPrefix) -or
    -not $federatedSubjectPrefix.StartsWith('repo:')
) {
    throw "GitHub did not return a valid OIDC subject prefix for '$Repository'."
}

$reviewerId = gh api "users/$RequiredReviewer" --jq '.id'
if (-not $reviewerId) {
    throw "Unable to resolve GitHub reviewer '$RequiredReviewer'."
}

$deployment = Get-Lab06Deployment
$values = ConvertFrom-DeploymentOutputs -Outputs $deployment.properties.outputs
$bootstrapResourceGroup = [string]$values.LAB04_BOOTSTRAP_RESOURCE_GROUP

Assert-Identity `
    -Name $values.LAB06_BUILD_IDENTITY_NAME `
    -ClientId $values.LAB06_BUILD_AZURE_CLIENT_ID `
    -PrincipalId $values.LAB06_BUILD_AZURE_PRINCIPAL_ID `
    -ResourceGroup $bootstrapResourceGroup
Assert-Identity `
    -Name $values.LAB06_DEPLOYMENT_IDENTITY_NAME `
    -ClientId $values.LAB06_DEPLOY_AZURE_CLIENT_ID `
    -PrincipalId $values.LAB06_DEPLOY_AZURE_PRINCIPAL_ID `
    -ResourceGroup $bootstrapResourceGroup

$registryId = az acr show `
    --name $values.LAB06_CONTAINER_REGISTRY_NAME `
    --resource-group $values.LAB04_PRIMARY_RESOURCE_GROUP `
    --query id `
    --output tsv
$containerAppId = az containerapp show `
    --name $values.LAB06_CONTAINER_APP_NAME `
    --resource-group $values.LAB04_SECONDARY_RESOURCE_GROUP `
    --query id `
    --output tsv
if ([string]::IsNullOrWhiteSpace($registryId)) {
    throw "Container registry '$($values.LAB06_CONTAINER_REGISTRY_NAME)' was not found."
}
if ([string]::IsNullOrWhiteSpace($containerAppId)) {
    throw "Container App '$($values.LAB06_CONTAINER_APP_NAME)' was not found."
}

Assert-RoleAssignment `
    -PrincipalId $values.LAB06_BUILD_AZURE_PRINCIPAL_ID `
    -Role AcrPush `
    -Scope $registryId
Assert-RoleAssignment `
    -PrincipalId $values.LAB06_DEPLOY_AZURE_PRINCIPAL_ID `
    -Role 'Container Apps Contributor' `
    -Scope $containerAppId
Assert-RoleAssignment `
    -PrincipalId $values.LAB06_DEPLOY_AZURE_PRINCIPAL_ID `
    -Role Reader `
    -Scope $values.FRONT_DOOR_PROFILE_ID

try {
    gh api `
        --method PUT `
        "repos/$Repository/environments/$buildEnvironment" `
        --silent
}
catch {
    throw "Failed to create GitHub environment '$buildEnvironment' in '$Repository'. Confirm that environments are supported by the repository plan and that the authenticated account has repository ADMIN permission. $($_.Exception.Message)"
}
Set-ProtectedEnvironment `
    -EnvironmentName $deployEnvironment `
    -ReviewerId ([long]$reviewerId) `
    -BranchName $DeploymentBranch

Set-FederatedCredential `
    -IdentityName $values.LAB06_BUILD_IDENTITY_NAME `
    -EnvironmentName $buildEnvironment `
    -ResourceGroup $bootstrapResourceGroup
Set-FederatedCredential `
    -IdentityName $values.LAB06_DEPLOYMENT_IDENTITY_NAME `
    -EnvironmentName $deployEnvironment `
    -ResourceGroup $bootstrapResourceGroup

$commonVariables = [ordered]@{
    AZURE_TENANT_ID = $tenantId
    AZURE_SUBSCRIPTION_ID = $SubscriptionId
    LAB06_CONTAINER_REGISTRY_NAME = $values.LAB06_CONTAINER_REGISTRY_NAME
    LAB06_CONTAINER_APP_NAME = $values.LAB06_CONTAINER_APP_NAME
    LAB06_RUNTIME_IDENTITY_RESOURCE_ID = $values.LAB06_RUNTIME_IDENTITY_RESOURCE_ID
    LAB06_RUNTIME_IDENTITY_CLIENT_ID = $values.LAB06_RUNTIME_IDENTITY_CLIENT_ID
    LAB04_PRIMARY_RESOURCE_GROUP = $values.LAB04_PRIMARY_RESOURCE_GROUP
    LAB04_SECONDARY_RESOURCE_GROUP = $values.LAB04_SECONDARY_RESOURCE_GROUP
    LAB04_GLOBAL_RESOURCE_GROUP = $values.LAB04_GLOBAL_RESOURCE_GROUP
    LAB04_PREFIX = $values.LAB04_PREFIX
    LAB04_SUFFIX = $values.LAB04_SUFFIX
}
$buildVariables = [ordered]@{ AZURE_CLIENT_ID = $values.LAB06_BUILD_AZURE_CLIENT_ID }
$deployVariables = [ordered]@{ AZURE_CLIENT_ID = $values.LAB06_DEPLOY_AZURE_CLIENT_ID }
foreach ($entry in $commonVariables.GetEnumerator()) {
    $buildVariables[$entry.Key] = $entry.Value
    $deployVariables[$entry.Key] = $entry.Value
}

Set-AndVerifyVariables `
    -EnvironmentName $buildEnvironment `
    -Variables $buildVariables
Set-AndVerifyVariables `
    -EnvironmentName $deployEnvironment `
    -Variables $deployVariables

Write-Host ''
Write-Host 'Lab 06 GitHub OIDC bootstrap completed.'
Write-Host "Repository: $Repository"
Write-Host "OIDC subject prefix: $federatedSubjectPrefix"
Write-Host "Azure deployment: $($deployment.name)"
Write-Host "Build environment and identity: $buildEnvironment / $($values.LAB06_BUILD_IDENTITY_NAME)"
Write-Host "Protected deployment environment and identity: $deployEnvironment / $($values.LAB06_DEPLOYMENT_IDENTITY_NAME)"
Write-Host "Required reviewer: $RequiredReviewer"
Write-Host "Deployment branch: $DeploymentBranch"

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
    [string]$SubscriptionId,

    [ValidatePattern('^[^/\s]+/[^/\s]+$')]
    [string]$Repository,

    [Parameter(Mandatory, ParameterSetName = 'Azd')]
    [ValidateNotNullOrEmpty()]
    [string]$AzdEnvironment,

    [Parameter(Mandatory, ParameterSetName = 'Arm')]
    [ValidateNotNullOrEmpty()]
    [ValidateLength(1, 64)]
    [ValidatePattern('^[a-zA-Z0-9._()\-]+$')]
    [string]$DeploymentName,

    [ValidateLength(1, 106)]
    [ValidatePattern('^[a-zA-Z0-9_-]+$')]
    [string]$GitHubEnvironment = 'lab04',

    [Parameter(Mandatory)]
    [ValidateLength(1, 39)]
    [ValidatePattern('^[a-zA-Z0-9](?:[a-zA-Z0-9]|-(?=[a-zA-Z0-9]))*$')]
    [string]$RequiredReviewer,

    [ValidateNotNullOrEmpty()]
    [string]$DeploymentBranch = 'main'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$requiredCommands = @('az', 'gh')
if ($PSCmdlet.ParameterSetName -eq 'Azd') {
    $requiredCommands += 'azd'
}
foreach ($command in $requiredCommands) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command '$command' was not found on PATH."
    }
}

az account set --subscription $SubscriptionId

if ($PSCmdlet.ParameterSetName -eq 'Arm') {
    $deployment = az deployment sub show `
        --name $DeploymentName `
        --output json | ConvertFrom-Json
    if ($deployment.properties.provisioningState -ne 'Succeeded') {
        throw "Subscription deployment '$DeploymentName' is not in Succeeded state."
    }

    $azdValues = @{}
    foreach ($output in $deployment.properties.outputs.PSObject.Properties) {
        $azdValues[$output.Name] = $output.Value.value
    }
    $azdValues['AZURE_ENV_NAME'] = [string]$deployment.properties.parameters.environmentName.value
}
else {
    azd env select $AzdEnvironment
    $azdValues = azd env get-values --output json | ConvertFrom-Json -AsHashtable
}

$requiredValues = @(
    'AZURE_ENV_NAME',
    'LAB04_BOOTSTRAP_RESOURCE_GROUP',
    'LAB04_PRIMARY_RESOURCE_GROUP',
    'LAB04_SECONDARY_RESOURCE_GROUP',
    'LAB04_GLOBAL_RESOURCE_GROUP',
    'LAB04_KEY_VAULT_NAME',
    'LAB04_DATABASE_MODE',
    'LAB04_SQL_MI_PRICING_MODEL',
    'LAB04_DATABASE_FQDN',
    'LAB04_CONTAINER_APPS_ENVIRONMENT_ID',
    'LAB04_PREFIX',
    'LAB04_PRIMARY_LOCATION',
    'LAB04_SECONDARY_LOCATION',
    'LAB04_APPLICATION_LOCATION',
    'LAB04_SQL_ADMIN_OBJECT_ID',
    'LAB04_SQL_ADMIN_LOGIN',
    'LAB04_SUFFIX',
    'LAB06_BUILD_AZURE_CLIENT_ID',
    'LAB06_BUILD_AZURE_PRINCIPAL_ID',
    'LAB06_BUILD_IDENTITY_NAME',
    'LAB06_DEPLOY_AZURE_CLIENT_ID',
    'LAB06_DEPLOY_AZURE_PRINCIPAL_ID',
    'LAB06_DEPLOYMENT_IDENTITY_NAME',
    'LAB06_RUNTIME_IDENTITY_NAME',
    'LAB06_RUNTIME_IDENTITY_RESOURCE_ID',
    'LAB06_RUNTIME_IDENTITY_CLIENT_ID',
    'LAB06_RUNTIME_IDENTITY_PRINCIPAL_ID',
    'LAB06_CONTAINER_REGISTRY_NAME',
    'LAB06_CONTAINER_APP_NAME',
    'LAB05_RETAIL_DATABASE_NAME'
)
$missingValues = @(
    $requiredValues | Where-Object { -not $azdValues[$_] }
)
if ($missingValues.Count -gt 0) {
    $sourceDescription = if ($PSCmdlet.ParameterSetName -eq 'Arm') {
        "subscription deployment '$DeploymentName'"
    }
    else {
        "AZD environment '$AzdEnvironment'"
    }
    $recovery = if ($PSCmdlet.ParameterSetName -eq 'Arm') {
        "Confirm the deployment name with 'az deployment sub list --output table', then rerun with -DeploymentName '<successful-deployment-name>'."
    }
    else {
        "If Lab 04 was deployed with Deploy-Lab04.ps1, rerun this script with -DeploymentName '<EnvironmentName>-deploy' instead of -AzdEnvironment."
    }
    throw "The selected $sourceDescription is missing required outputs: $($missingValues -join ', '). $recovery"
}

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
    throw "GitHub environment configuration requires ADMIN permission on '$Repository'. The authenticated account has '$($repositoryInfo.viewerPermission)' permission. Ask a repository administrator to run this script or rerun it with -Repository 'owner/name' for a repository you administer."
}

$tenantId = az account show --query tenantId --output tsv
$subscriptionScope = "/subscriptions/$SubscriptionId"
$infrastructurePreviewEnvironment = $GitHubEnvironment
$infrastructureDeployEnvironment = "$GitHubEnvironment-deploy"
$codeBuildEnvironment = 'lab06'
$codeDeployEnvironment = 'lab06-deploy'

function Get-OrCreateIdentity {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Location
    )

    $identity = az identity list `
        --resource-group $azdValues.LAB04_BOOTSTRAP_RESOURCE_GROUP `
        --query "[?name=='$Name'] | [0]" `
        --output json | ConvertFrom-Json
    if ($null -eq $identity) {
        $identity = az identity create `
            --name $Name `
            --resource-group $azdValues.LAB04_BOOTSTRAP_RESOURCE_GROUP `
            --location $Location `
            --output json | ConvertFrom-Json
    }
    return $identity
}

function Add-RoleAssignmentIfMissing {
    param(
        [Parameter(Mandatory)][string]$PrincipalId,
        [Parameter(Mandatory)][string]$Role,
        [Parameter(Mandatory)][string]$Scope
    )

    $count = az role assignment list `
        --scope $Scope `
        --query "[?principalId=='$PrincipalId' && roleDefinitionName=='$Role'] | length(@)" `
        --output tsv
    if ([int]$count -ne 0) {
        return
    }

    for ($attempt = 1; $attempt -le 12; $attempt++) {
        try {
            az role assignment create `
                --assignee-object-id $PrincipalId `
                --assignee-principal-type ServicePrincipal `
                --role $Role `
                --scope $Scope `
                --output none
            return
        }
        catch {
            if ($attempt -eq 12) {
                throw
            }
            Start-Sleep -Seconds 10
        }
    }
}

function Remove-RoleAssignmentIfPresent {
    param(
        [Parameter(Mandatory)][string]$PrincipalId,
        [Parameter(Mandatory)][string]$Role,
        [Parameter(Mandatory)][string]$Scope
    )

    $assignmentIds = az role assignment list `
        --assignee-object-id $PrincipalId `
        --scope $Scope `
        --query "[?roleDefinitionName=='$Role'].id" `
        --output tsv
    foreach ($assignmentId in $assignmentIds) {
        if ($assignmentId) {
            az role assignment delete --ids $assignmentId --output none
        }
    }
}

function Set-FederatedCredential {
    param(
        [Parameter(Mandatory)][string]$IdentityName,
        [Parameter(Mandatory)][string]$EnvironmentName
    )

    $credentialName = "github-$EnvironmentName"
    $subject = "repo:$Repository`:environment:$EnvironmentName"
    $credentials = az identity federated-credential list `
        --identity-name $IdentityName `
        --resource-group $azdValues.LAB04_BOOTSTRAP_RESOURCE_GROUP `
        --output json | ConvertFrom-Json
    foreach ($credential in $credentials) {
        if ($credential.name -like 'github-*' -and $credential.name -ne $credentialName) {
            az identity federated-credential delete `
                --name $credential.name `
                --identity-name $IdentityName `
                --resource-group $azdValues.LAB04_BOOTSTRAP_RESOURCE_GROUP `
                --yes
        }
    }

    $existing = $credentials | Where-Object name -EQ $credentialName
    if ($null -eq $existing) {
        az identity federated-credential create `
            --name $credentialName `
            --identity-name $IdentityName `
            --resource-group $azdValues.LAB04_BOOTSTRAP_RESOURCE_GROUP `
            --issuer 'https://token.actions.githubusercontent.com' `
            --subject $subject `
            --audiences 'api://AzureADTokenExchange' `
            --output none
        return
    }

    az identity federated-credential update `
        --name $credentialName `
        --identity-name $IdentityName `
        --resource-group $azdValues.LAB04_BOOTSTRAP_RESOURCE_GROUP `
        --issuer 'https://token.actions.githubusercontent.com' `
        --subject $subject `
        --audiences 'api://AzureADTokenExchange' `
        --output none
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

$reviewerId = gh api "users/$RequiredReviewer" --jq '.id'
if (-not $reviewerId) {
    throw "Unable to resolve GitHub reviewer '$RequiredReviewer'."
}

$infrastructurePreviewIdentity = Get-OrCreateIdentity `
    -Name "$($azdValues.LAB04_PREFIX)-preview-$($azdValues.LAB04_SUFFIX)" `
    -Location $azdValues.LAB04_PRIMARY_LOCATION
$infrastructureDeployIdentity = Get-OrCreateIdentity `
    -Name "$($azdValues.LAB04_PREFIX)-deploy-$($azdValues.LAB04_SUFFIX)" `
    -Location $azdValues.LAB04_PRIMARY_LOCATION

$resourceGroups = @(
    $azdValues.LAB04_BOOTSTRAP_RESOURCE_GROUP,
    $azdValues.LAB04_PRIMARY_RESOURCE_GROUP,
    $azdValues.LAB04_SECONDARY_RESOURCE_GROUP,
    $azdValues.LAB04_GLOBAL_RESOURCE_GROUP
)
foreach ($resourceGroup in $resourceGroups) {
    $scope = "$subscriptionScope/resourceGroups/$resourceGroup"
    Add-RoleAssignmentIfMissing `
        -PrincipalId $infrastructurePreviewIdentity.principalId `
        -Role Reader `
        -Scope $scope
    Add-RoleAssignmentIfMissing `
        -PrincipalId $infrastructureDeployIdentity.principalId `
        -Role Contributor `
        -Scope $scope
    Add-RoleAssignmentIfMissing `
        -PrincipalId $infrastructureDeployIdentity.principalId `
        -Role 'Role Based Access Control Administrator' `
        -Scope $scope
}

$deploymentRoleName = "Lab 04 AZD Deployment Operator $($azdValues.LAB04_SUFFIX)"
$deploymentRole = @(
    az role definition list --name $deploymentRoleName --output json |
        ConvertFrom-Json
)
if ($deploymentRole.Count -eq 0) {
    $deploymentRoleDefinition = @{
        Name = $deploymentRoleName
        Description = 'Runs Lab 04 ARM deployments and creates or updates resource-group shells without managing their contents.'
        Actions = @(
            'Microsoft.Resources/deployments/*'
            'Microsoft.Resources/subscriptions/resourceGroups/read'
            'Microsoft.Resources/subscriptions/resourceGroups/write'
        )
        NotActions = @()
        DataActions = @()
        NotDataActions = @()
        AssignableScopes = @($subscriptionScope)
    } | ConvertTo-Json -Depth 5 -Compress
    $temporaryRoleDefinitionPath = Join-Path `
        ([System.IO.Path]::GetTempPath()) `
        "lab04-role-$([Guid]::NewGuid().ToString('N')).json"
    try {
        [System.IO.File]::WriteAllText(
            $temporaryRoleDefinitionPath,
            $deploymentRoleDefinition,
            [System.Text.UTF8Encoding]::new($false)
        )
        az role definition create `
            --role-definition $temporaryRoleDefinitionPath `
            --output none
    }
    finally {
        if (Test-Path -LiteralPath $temporaryRoleDefinitionPath) {
            Remove-Item -LiteralPath $temporaryRoleDefinitionPath -Force
        }
    }
}
Add-RoleAssignmentIfMissing `
    -PrincipalId $infrastructureDeployIdentity.principalId `
    -Role $deploymentRoleName `
    -Scope $subscriptionScope

$keyVaultScope = "$subscriptionScope/resourceGroups/$($azdValues.LAB04_BOOTSTRAP_RESOURCE_GROUP)/providers/Microsoft.KeyVault/vaults/$($azdValues.LAB04_KEY_VAULT_NAME)"
Add-RoleAssignmentIfMissing `
    -PrincipalId $infrastructureDeployIdentity.principalId `
    -Role 'Key Vault Secrets User' `
    -Scope $keyVaultScope

$registryId = az acr show `
    --name $azdValues.LAB06_CONTAINER_REGISTRY_NAME `
    --resource-group $azdValues.LAB04_PRIMARY_RESOURCE_GROUP `
    --query id `
    --output tsv
Remove-RoleAssignmentIfPresent `
    -PrincipalId $azdValues.LAB06_DEPLOY_AZURE_PRINCIPAL_ID `
    -Role AcrPush `
    -Scope $registryId

foreach ($environmentName in @($infrastructurePreviewEnvironment, $codeBuildEnvironment)) {
    try {
        gh api `
            --method PUT `
            "repos/$Repository/environments/$environmentName" `
            --silent
    }
    catch {
        throw "Failed to create GitHub environment '$environmentName' in '$Repository'. Confirm that environments are supported by the repository plan and that the authenticated account has repository ADMIN permission. $($_.Exception.Message)"
    }
}
Set-ProtectedEnvironment `
    -EnvironmentName $infrastructureDeployEnvironment `
    -ReviewerId ([long]$reviewerId) `
    -BranchName $DeploymentBranch
Set-ProtectedEnvironment `
    -EnvironmentName $codeDeployEnvironment `
    -ReviewerId ([long]$reviewerId) `
    -BranchName $DeploymentBranch

Set-FederatedCredential `
    -IdentityName $infrastructurePreviewIdentity.name `
    -EnvironmentName $infrastructurePreviewEnvironment
Set-FederatedCredential `
    -IdentityName $infrastructureDeployIdentity.name `
    -EnvironmentName $infrastructureDeployEnvironment
Set-FederatedCredential `
    -IdentityName $azdValues.LAB06_BUILD_IDENTITY_NAME `
    -EnvironmentName $codeBuildEnvironment
Set-FederatedCredential `
    -IdentityName $azdValues.LAB06_DEPLOYMENT_IDENTITY_NAME `
    -EnvironmentName $codeDeployEnvironment

$commonLab04Variables = [ordered]@{
    AZURE_TENANT_ID = $tenantId
    AZURE_SUBSCRIPTION_ID = $SubscriptionId
    AZD_ENVIRONMENT = $azdValues.AZURE_ENV_NAME
    LAB04_BOOTSTRAP_RESOURCE_GROUP = $azdValues.LAB04_BOOTSTRAP_RESOURCE_GROUP
    LAB04_PRIMARY_RESOURCE_GROUP = $azdValues.LAB04_PRIMARY_RESOURCE_GROUP
    LAB04_SECONDARY_RESOURCE_GROUP = $azdValues.LAB04_SECONDARY_RESOURCE_GROUP
    LAB04_GLOBAL_RESOURCE_GROUP = $azdValues.LAB04_GLOBAL_RESOURCE_GROUP
    LAB04_PREFIX = $azdValues.LAB04_PREFIX
    LAB04_PRIMARY_LOCATION = $azdValues.LAB04_PRIMARY_LOCATION
    LAB04_SECONDARY_LOCATION = $azdValues.LAB04_SECONDARY_LOCATION
    LAB04_APPLICATION_LOCATION = $azdValues.LAB04_APPLICATION_LOCATION
    LAB04_SQL_ADMIN_OBJECT_ID = $azdValues.LAB04_SQL_ADMIN_OBJECT_ID
    LAB04_SQL_ADMIN_LOGIN = $azdValues.LAB04_SQL_ADMIN_LOGIN
    LAB04_SUFFIX = $azdValues.LAB04_SUFFIX
    LAB04_KEY_VAULT_NAME = $azdValues.LAB04_KEY_VAULT_NAME
    LAB04_DATABASE_MODE = $azdValues.LAB04_DATABASE_MODE
    LAB04_SQL_MI_PRICING_MODEL = $azdValues.LAB04_SQL_MI_PRICING_MODEL
    LAB06_BUILD_AZURE_PRINCIPAL_ID = $azdValues.LAB06_BUILD_AZURE_PRINCIPAL_ID
    LAB06_DEPLOY_AZURE_PRINCIPAL_ID = $azdValues.LAB06_DEPLOY_AZURE_PRINCIPAL_ID
    LAB06_RUNTIME_IDENTITY_RESOURCE_ID = $azdValues.LAB06_RUNTIME_IDENTITY_RESOURCE_ID
    LAB06_RUNTIME_IDENTITY_CLIENT_ID = $azdValues.LAB06_RUNTIME_IDENTITY_CLIENT_ID
}
foreach ($environmentName in @($infrastructurePreviewEnvironment, $infrastructureDeployEnvironment)) {
    foreach ($entry in $commonLab04Variables.GetEnumerator()) {
        gh variable set $entry.Key --env $environmentName --repo $Repository --body $entry.Value
    }
}
gh variable set AZURE_CLIENT_ID `
    --env $infrastructurePreviewEnvironment `
    --repo $Repository `
    --body $infrastructurePreviewIdentity.clientId
gh variable set AZURE_CLIENT_ID `
    --env $infrastructureDeployEnvironment `
    --repo $Repository `
    --body $infrastructureDeployIdentity.clientId

$commonLab06Variables = [ordered]@{
    AZURE_TENANT_ID = $tenantId
    AZURE_SUBSCRIPTION_ID = $SubscriptionId
    LAB04_PRIMARY_RESOURCE_GROUP = $azdValues.LAB04_PRIMARY_RESOURCE_GROUP
    LAB04_SECONDARY_RESOURCE_GROUP = $azdValues.LAB04_SECONDARY_RESOURCE_GROUP
    LAB04_GLOBAL_RESOURCE_GROUP = $azdValues.LAB04_GLOBAL_RESOURCE_GROUP
    LAB04_DATABASE_MODE = $azdValues.LAB04_DATABASE_MODE
    LAB04_DATABASE_FQDN = $azdValues.LAB04_DATABASE_FQDN
    LAB05_RETAIL_DATABASE_NAME = $azdValues.LAB05_RETAIL_DATABASE_NAME
    LAB06_RUNTIME_IDENTITY_RESOURCE_ID = $azdValues.LAB06_RUNTIME_IDENTITY_RESOURCE_ID
    LAB06_RUNTIME_IDENTITY_CLIENT_ID = $azdValues.LAB06_RUNTIME_IDENTITY_CLIENT_ID
    LAB06_CONTAINER_REGISTRY_NAME = $azdValues.LAB06_CONTAINER_REGISTRY_NAME
    LAB06_CONTAINER_APP_NAME = $azdValues.LAB06_CONTAINER_APP_NAME
}
foreach ($environmentName in @($codeBuildEnvironment, $codeDeployEnvironment)) {
    foreach ($entry in $commonLab06Variables.GetEnumerator()) {
        gh variable set $entry.Key --env $environmentName --repo $Repository --body $entry.Value
    }
}
gh variable set AZURE_CLIENT_ID `
    --env $codeBuildEnvironment `
    --repo $Repository `
    --body $azdValues.LAB06_BUILD_AZURE_CLIENT_ID
gh variable set AZURE_CLIENT_ID `
    --env $codeDeployEnvironment `
    --repo $Repository `
    --body $azdValues.LAB06_DEPLOY_AZURE_CLIENT_ID

Write-Host "GitHub OIDC configuration completed for $Repository."
Write-Host "Protected deployment branch: $DeploymentBranch"
Write-Host "Required reviewer: $RequiredReviewer"

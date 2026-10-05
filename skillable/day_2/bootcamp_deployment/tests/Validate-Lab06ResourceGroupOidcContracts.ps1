[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Resolve-Path (Join-Path $projectRoot '..\..\..')
$repositoryScriptPath = Join-Path `
    $repositoryRoot `
    'assets\scripts\Initialize-Lab06RepositoryFromResourceGroups.ps1'
$hostedScriptPath = Join-Path `
    $projectRoot `
    'assets\scripts\Initialize-Lab06RepositoryFromResourceGroups.ps1'
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contract {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $Condition) {
        $failures.Add($Message)
    }
}

foreach ($path in @($repositoryScriptPath, $hostedScriptPath)) {
    Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) `
        "Missing resource-group OIDC script '$path'."
}
if ($failures.Count -gt 0) {
    throw "Lab 06 resource-group OIDC validation failed:`n- $($failures -join "`n- ")"
}

$repositoryScript = Get-Content -LiteralPath $repositoryScriptPath -Raw
$hostedScript = Get-Content -LiteralPath $hostedScriptPath -Raw
Assert-Contract ($repositoryScript -ceq $hostedScript) `
    'The repository and hosted resource-group OIDC scripts must remain identical.'

$command = Get-Command $repositoryScriptPath
foreach ($name in @(
    'SubscriptionId',
    'Repository',
    'BootstrapResourceGroup',
    'PrimaryResourceGroup',
    'SecondaryResourceGroup',
    'GlobalResourceGroup',
    'BootstrapDeploymentName',
    'PrimaryDeploymentName',
    'SecondaryDeploymentName',
    'GlobalDeploymentName',
    'RequiredReviewer',
    'DeploymentBranch'
)) {
    Assert-Contract ($name -in $command.Parameters.Keys) `
        "Resource-group OIDC script is missing parameter '$name'."
}

foreach ($name in @(
    'SubscriptionId',
    'BootstrapResourceGroup',
    'PrimaryResourceGroup',
    'SecondaryResourceGroup',
    'GlobalResourceGroup',
    'RequiredReviewer'
)) {
    $parameter = $command.Parameters[$name]
    $mandatory = @(
        $parameter.Attributes |
            Where-Object {
                $_ -is [System.Management.Automation.ParameterAttribute] -and
                $_.Mandatory
            }
    )
    Assert-Contract ($mandatory.Count -gt 0) `
        "Resource-group OIDC parameter '$name' must be mandatory."
}

Assert-Contract (
    $repositoryScript -match 'az deployment group list' -and
    $repositoryScript -match 'az deployment group show' -and
    $repositoryScript -notmatch 'az deployment sub (list|show)'
) 'Resource-group OIDC discovery must use resource-group deployment records only.'
Assert-Contract (
    $repositoryScript -match 'properties\.timestamp' -and
    $repositoryScript -match 'Descending = \$true'
) 'Resource-group OIDC discovery must select the newest successful matching deployment.'

foreach ($output in @(
    'codeBuildIdentityName',
    'codeBuildClientId',
    'codeBuildPrincipalId',
    'codeDeploymentIdentityName',
    'codeDeploymentClientId',
    'codeDeploymentPrincipalId',
    'runtimeIdentityName',
    'runtimeIdentityId',
    'runtimeIdentityClientId',
    'runtimeIdentityPrincipalId',
    'containerRegistryName',
    'containerAppName',
    'containerAppsEnvironmentId',
    'retailDatabaseName',
    'frontDoorProfileId'
)) {
    Assert-Contract ($repositoryScript -match "'$output'") `
        "Resource-group OIDC discovery contract is missing output '$output'."
}

Assert-Contract (
    $repositoryScript -match 'Get-RequiredDeploymentParameter' -and
    $repositoryScript -match 'distinctPrefixes' -and
    $repositoryScript -match 'distinctSuffixes' -and
    $repositoryScript -match 'do not belong to one Lab 04 boundary'
) 'Selected resource-group deployments must enforce consistent prefix and suffix parameters.'
Assert-Contract (
    $repositoryScript -match 'Assert-Identity' -and
    $repositoryScript -match 'LAB06_RUNTIME_IDENTITY_RESOURCE_ID' -and
    $repositoryScript -match 'az acr show' -and
    $repositoryScript -match 'az containerapp show' -and
    $repositoryScript -match 'az resource show'
) 'Resource-group OIDC setup must validate identities, ACR, Container App, and Front Door.'
foreach ($role in @('AcrPush', 'Container Apps Contributor', 'Reader')) {
    Assert-Contract ($repositoryScript -match [regex]::Escape($role)) `
        "Resource-group OIDC setup must validate role '$role'."
}
Assert-Contract (
    $repositoryScript -match "'lab06'" -and
    $repositoryScript -match "'lab06-deploy'" -and
    $repositoryScript -match 'Set-FederatedCredential' -and
    $repositoryScript -match 'Set-ProtectedEnvironment' -and
    $repositoryScript -match 'Set-AndVerifyVariables'
) 'Resource-group OIDC setup must preserve the Lab 06 GitHub environment contract.'
foreach ($variable in @(
    'AZURE_CLIENT_ID',
    'AZURE_TENANT_ID',
    'AZURE_SUBSCRIPTION_ID',
    'LAB06_CONTAINER_REGISTRY_NAME',
    'LAB06_CONTAINER_APP_NAME',
    'LAB06_RUNTIME_IDENTITY_RESOURCE_ID',
    'LAB06_RUNTIME_IDENTITY_CLIENT_ID',
    'LAB04_PRIMARY_RESOURCE_GROUP',
    'LAB04_SECONDARY_RESOURCE_GROUP',
    'LAB04_GLOBAL_RESOURCE_GROUP',
    'LAB04_PREFIX',
    'LAB04_SUFFIX'
)) {
    Assert-Contract ($repositoryScript -match $variable) `
        "Resource-group OIDC setup must publish '$variable'."
}

if ($failures.Count -gt 0) {
    throw "Lab 06 resource-group OIDC validation failed:`n- $($failures -join "`n- ")"
}

Write-Host 'Lab 06 resource-group OIDC contracts are valid.'

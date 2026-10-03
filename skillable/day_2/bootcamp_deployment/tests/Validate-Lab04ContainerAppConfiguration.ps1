[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Resolve-Path (Join-Path $projectRoot '..\..\..')
$bootstrapPath = Join-Path $projectRoot 'infra\lab04\complete\bootstrap.bicep'
$containerModulePath = Join-Path `
    $projectRoot `
    'infra\lab04\complete\modules\container-app-region.bicep'
$regionalNetworkPath = Join-Path `
    $projectRoot `
    'infra\lab04\complete\modules\regional-network.bicep'
$secondaryPath = Join-Path $projectRoot 'infra\lab04\complete\secondary.bicep'
$mainPath = Join-Path $projectRoot 'infra\main.bicep'
$configurePath = Join-Path `
    $projectRoot `
    'assets\scripts\Configure-Lab04GitHub.ps1'
$retailWorkflowPath = Join-Path `
    $repositoryRoot `
    'assets\solutions\lab06\lab06-retail-cicd.yml'
$foundationWorkflowPath = Join-Path `
    $repositoryRoot `
    '.github\workflows\lab04-deploy.yml'
$migrationLabPath = Join-Path `
    $repositoryRoot `
    'labs\day-2\05-modernize-data\README.md'
$lab06BootstrapPath = Join-Path `
    $repositoryRoot `
    'assets\scripts\Initialize-Lab06Repository.ps1'

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

$bootstrap = Get-Content -LiteralPath $bootstrapPath -Raw
$containerModule = Get-Content -LiteralPath $containerModulePath -Raw
$regionalNetwork = Get-Content -LiteralPath $regionalNetworkPath -Raw
$secondary = Get-Content -LiteralPath $secondaryPath -Raw
$main = Get-Content -LiteralPath $mainPath -Raw
$configure = Get-Content -LiteralPath $configurePath -Raw
$retailWorkflow = Get-Content -LiteralPath $retailWorkflowPath -Raw
$foundationWorkflow = Get-Content -LiteralPath $foundationWorkflowPath -Raw
$migrationLab = Get-Content -LiteralPath $migrationLabPath -Raw
$lab06Bootstrap = Get-Content -LiteralPath $lab06BootstrapPath -Raw

Assert-Contract (
    $bootstrap -match 'runtimeIdentity.*Microsoft\.ManagedIdentity/userAssignedIdentities' -and
    $bootstrap -match '4633458b-17de-408a-b874-0445c86b69e6' -and
    $bootstrap -match 'runtimeIdentityPrincipalId'
) 'Bootstrap must create the runtime identity, grant Key Vault Secrets User, and expose its principal ID.'

foreach ($name in @(
    'LAB06_RUNTIME_IDENTITY_NAME',
    'LAB06_RUNTIME_IDENTITY_RESOURCE_ID',
    'LAB06_RUNTIME_IDENTITY_CLIENT_ID',
    'LAB06_RUNTIME_IDENTITY_PRINCIPAL_ID',
    'LAB05_RETAIL_DATABASE_NAME'
)) {
    Assert-Contract ($main -match "(?m)^output $name string") `
        "main.bicep is missing output '$name'."
    Assert-Contract ($configure -match "'$name'") `
        "Configure-Lab04GitHub.ps1 does not require output '$name'."
}

Assert-Contract (
    $main -match "(?m)^var databaseName = 'eshop_ai'\r?$" -and
    $secondary -match "(?m)^var retailDatabaseName = 'eshop'\r?$"
) 'The BACPAC database eshop_ai and migrated retail database eshop must remain distinct.'

foreach ($name in @(
    'ASPNETCORE_ENVIRONMENT',
    'AZURE_CLIENT_ID',
    'ConnectionStrings__StoreDbContext'
)) {
    Assert-Contract ($containerModule -match "name: '$name'") `
        "The Container App template is missing environment variable '$name'."
}
Assert-Contract (
    $containerModule -match 'Initial Catalog=\$\{retailDatabaseName\}' -and
    $containerModule -match 'Authentication=Active Directory Managed Identity' -and
    $containerModule -match 'User Id=\$\{runtimeIdentityClientId\}' -and
    $containerModule -match 'TrustServerCertificate=False'
) 'The retail connection string must use the user-assigned identity and strict TLS.'
Assert-Contract (
    $containerModule -match 'keyVaultUrl: secret\.keyVaultUrl' -and
    $containerModule -match 'identity: runtimeIdentityResourceId' -and
    $containerModule -match 'secretRef: secret\.name'
) 'The Container App template must support Key Vault-backed secret references.'
Assert-Contract (
    $containerModule -notmatch '(?s)for secret in keyVaultSecretReferences:\s*\{[^}]*value:'
) 'Key Vault secret-reference objects must never contain literal secret values.'
Assert-Contract (
    $containerModule -match "server: containerRegistryLoginServer\s+identity: runtimeIdentityResourceId" -and
    $containerModule -notmatch "identity: 'system'" -and
    $secondary -match 'principalId: runtimeIdentityPrincipalId' -and
    $secondary -match 'dependsOn:\s*\[\s*registryPull\s*\]'
) 'ACR pull access must use the pre-authorized runtime identity before the Container App is created.'
Assert-Contract (
    $containerModule -match '(?m)^\s*zoneRedundant: false\s*$' -and
    $containerModule -notmatch '(?m)^\s*zoneRedundant: true\s*$'
) 'The sample Container Apps environment must explicitly disable zone redundancy.'
Assert-Contract (
    $secondary -match "retailDatabaseFqdn: databaseMode == 'azureSql'\s+\? primaryDatabaseFqdn\s+: ''" -and
    $secondary -notmatch 'retailDatabaseFqdn:[^\r\n]*managedInstance' -and
    $main -match 'runtimeIdentityPrincipalId: bootstrap\.outputs\.runtimeIdentityPrincipalId'
) 'Container Apps must not wait for SQL Managed Instance provisioning.'
Assert-Contract (
    $regionalNetwork -match 'mi-healthprobe-in-' -and
    $regionalNetwork -match 'mi-internal-in-' -and
    $regionalNetwork -match 'mi-internal-out-' -and
    $regionalNetwork -match 'subnet-\$\{managedInstanceAddressToken\}' -and
    $regionalNetwork.Contains(
        "var managedInstanceAddressToken = replace(replace(managedInstanceAddressPrefix, '.', '-'), '/', '-')"
    ) -and
    $regionalNetwork -notmatch '(?m)^\s*routes:\s*\[\]\s*$'
) 'SQL MI networking must declare the Network Intent Policy rules and exact-match route on reruns.'

Assert-Contract (
    $retailWorkflow -notmatch '--set-env-vars' -and
    $retailWorkflow -notmatch 'az containerapp registry set' -and
    $retailWorkflow -notmatch 'name_token=' -and
    $retailWorkflow -match 'az containerapp update' -and
    $retailWorkflow -match '--image "\$IMAGE_REFERENCE"'
) 'The retail workflow must update only the image, not runtime configuration or registry settings.'
Assert-Contract (
    $retailWorkflow -match 'identity\.userAssignedIdentities' -and
    $retailWorkflow -match 'ConnectionStrings__StoreDbContext'
) 'The retail workflow must verify the Bicep-owned identity and environment-variable contract.'
Assert-Contract (
    $retailWorkflow -match 'SOLUTION: labs/day-1/04-deploy-to-azure/sample-app/eShopLiteFx\.sln' -and
    $retailWorkflow -notmatch 'labs/day-1/03-modernize-with-ghcp/sample-app'
) 'The retail workflow must build the documented Lab 04 application end state.'
foreach ($name in @(
    'LAB06_RUNTIME_IDENTITY_RESOURCE_ID',
    'LAB06_RUNTIME_IDENTITY_CLIENT_ID'
)) {
    Assert-Contract (
        $lab06Bootstrap -match "'$name'" -and
        $lab06Bootstrap -match "$name = [`$]values\.$name"
    ) "Initialize-Lab06Repository.ps1 must require and publish '$name'."
}
Assert-Contract (
    $foundationWorkflow -match 'runtimeIdentityResourceId=' -and
    $foundationWorkflow -match 'runtimeIdentityClientId='
) 'The complete foundation workflow must pass the runtime identity to secondary Bicep.'

Assert-Contract (
    $migrationLab -match 'LAB06_RUNTIME_IDENTITY_RESOURCE_ID' -and
    $migrationLab -match 'WITH OBJECT_ID' -and
    $migrationLab -match 'ALTER ROLE db_datareader' -and
    $migrationLab -match 'ALTER ROLE db_datawriter' -and
    $migrationLab -notmatch 'ALTER ROLE db_owner' -and
    $migrationLab -notmatch 'ALTER ROLE db_ddladmin'
) 'Lab 05 must grant the runtime identity only the approved post-migration database roles.'

if ($failures.Count -gt 0) {
    throw "Lab 04 Container App configuration validation failed:`n- $($failures -join "`n- ")"
}

Write-Host 'Lab 04 Container App configuration contracts are valid.'

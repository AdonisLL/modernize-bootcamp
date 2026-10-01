[CmdletBinding(DefaultParameterSetName = 'Azd')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Azd')]
    [ValidateNotNullOrEmpty()]
    [string]$AzdEnvironment,

    [Parameter(Mandatory, ParameterSetName = 'Arm')]
    [ValidateLength(1, 64)]
    [ValidatePattern('^[a-zA-Z0-9._()\-]+$')]
    [string]$DeploymentName,

    [string]$BacpacPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

. (Join-Path $PSScriptRoot 'Lab04DatabaseImport.ps1')

$parameterSetName = $PSCmdlet.ParameterSetName

function Get-Lab04DeploymentValues {
    if ($parameterSetName -eq 'Arm') {
        $deployment = az deployment sub show `
            --name $DeploymentName `
            --output json | ConvertFrom-Json
        if ($deployment.properties.provisioningState -ne 'Succeeded') {
            throw "Subscription deployment '$DeploymentName' is not in Succeeded state."
        }

        $values = @{}
        foreach ($output in $deployment.properties.outputs.PSObject.Properties) {
            $values[$output.Name] = $output.Value.value
        }
        $values['AZURE_ENV_NAME'] = [string]$deployment.properties.parameters.environmentName.value
        return $values
    }

    azd env select $AzdEnvironment
    return azd env get-values --output json | ConvertFrom-Json -AsHashtable
}

function Add-CleanupFailure {
    param(
        [Parameter(Mandatory)][System.Collections.Generic.List[string]]$Failures,
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $Failures.Add("$Action failed: $($ErrorRecord.Exception.Message)")
}

$requiredCommands = @('az')
if ($parameterSetName -eq 'Azd') {
    $requiredCommands += 'azd'
}
foreach ($command in $requiredCommands) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command '$command' was not found on PATH."
    }
}

az account show --output none
$account = az account show --query '{id:id,user:user.name}' --output json |
    ConvertFrom-Json

$values = Get-Lab04DeploymentValues
$requiredValues = @(
    'AZURE_ENV_NAME',
    'LAB04_DATABASE_MODE',
    'LAB04_DATABASE_NAME',
    'LAB04_DATABASE_RESOURCE_GROUP',
    'LAB04_DATABASE_SERVER_NAME',
    'LAB04_DATABASE_FQDN'
)
if ($values['LAB04_DATABASE_MODE'] -eq 'sqlMi') {
    $requiredValues += @('LAB04_SQL_MI_NSG_NAME', 'LAB04_SQL_MI_PUBLIC_ENDPOINT')
}
$missingValues = @(
    $requiredValues | Where-Object {
        [string]::IsNullOrWhiteSpace([string]$values[$_])
    }
)
if ($missingValues.Count -gt 0) {
    throw "The selected deployment is missing required database outputs: $($missingValues -join ', ')."
}

$databaseMode = [string]$values['LAB04_DATABASE_MODE']
if ($databaseMode -notin @('azureSql', 'sqlMi')) {
    throw "Unsupported database mode '$databaseMode'."
}
$databaseName = [string]$values['LAB04_DATABASE_NAME']
if ($databaseName -cne 'eshop_ai') {
    throw "Expected database name 'eshop_ai', but the deployment returned '$databaseName'."
}

if (-not $BacpacPath) {
    $projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $repositoryRoot = Resolve-Path (Join-Path $projectRoot '..\..\..')
    $BacpacPath = Join-Path $repositoryRoot 'data\eshop.bacpac'
}
if (-not (Test-Path -LiteralPath $BacpacPath -PathType Leaf)) {
    throw "The eShop BACPAC was not found at '$BacpacPath'."
}
$BacpacPath = (Resolve-Path -LiteralPath $BacpacPath).Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

$resourceGroupName = [string]$values['LAB04_DATABASE_RESOURCE_GROUP']
$serverName = [string]$values['LAB04_DATABASE_SERVER_NAME']
$existingDatabaseCount = if ($databaseMode -eq 'azureSql') {
    az sql db list `
        --resource-group $resourceGroupName `
        --server $serverName `
        --query "[?name=='$databaseName'] | length(@)" `
        --output tsv
}
else {
    az sql midb list `
        --resource-group $resourceGroupName `
        --managed-instance $serverName `
        --query "[?name=='$databaseName'] | length(@)" `
        --output tsv
}
if ([int]$existingDatabaseCount -gt 0) {
    Write-Host "Database '$databaseName' already exists on '$serverName'; preserving it and skipping BACPAC import."
    return
}

$sqlPackagePath = Resolve-Lab04SqlPackage -ProjectRoot $projectRoot
$publicIpAddress = (
    Invoke-RestMethod -Uri 'https://api.ipify.org' -Method Get -TimeoutSec 15
).ToString().Trim()
if (-not (Test-Lab04PublicIPv4Address -IpAddress $publicIpAddress)) {
    throw "api.ipify.org returned invalid public IPv4 address '$publicIpAddress'."
}

$ruleName = New-Lab04DatabaseImportRuleName `
    -SubscriptionId ([string]$account.id) `
    -EnvironmentName ([string]$values['AZURE_ENV_NAME']) `
    -DatabaseMode $databaseMode
$ruleCreated = $false
$restoreAzureSqlPublicAccess = $false
$operationError = $null
$cleanupFailures = [System.Collections.Generic.List[string]]::new()

try {
    if ($databaseMode -eq 'azureSql') {
        $publicNetworkAccess = az sql server show `
            --resource-group $resourceGroupName `
            --name $serverName `
            --query publicNetworkAccess `
            --output tsv
        if ($publicNetworkAccess -eq 'Disabled') {
            az sql server update `
                --resource-group $resourceGroupName `
                --name $serverName `
                --enable-public-network true `
                --output none
            $restoreAzureSqlPublicAccess = $true
        }

        az sql server firewall-rule create `
            --resource-group $resourceGroupName `
            --server $serverName `
            --name $ruleName `
            --start-ip-address $publicIpAddress `
            --end-ip-address $publicIpAddress `
            --output none
        $ruleCreated = $true
        $targetServer = [string]$values['LAB04_DATABASE_FQDN']
    }
    else {
        $networkSecurityGroupName = [string]$values['LAB04_SQL_MI_NSG_NAME']
        az network nsg rule create `
            --resource-group $resourceGroupName `
            --nsg-name $networkSecurityGroupName `
            --name $ruleName `
            --priority 1200 `
            --access Allow `
            --direction Inbound `
            --protocol Tcp `
            --source-address-prefixes "$publicIpAddress/32" `
            --source-port-ranges '*' `
            --destination-address-prefixes '*' `
            --destination-port-ranges 3342 `
            --description 'Temporary BACPAC import access; removed by deployment automation.' `
            --output none
        $ruleCreated = $true
        $targetServer = [string]$values['LAB04_SQL_MI_PUBLIC_ENDPOINT']
    }

    $accessToken = az account get-access-token `
        --resource 'https://database.windows.net/' `
        --query accessToken `
        --output tsv
    if ([string]::IsNullOrWhiteSpace($accessToken)) {
        throw 'Azure CLI did not return an Azure SQL access token.'
    }

    $sqlPackageArguments = @(
        '/Action:Import'
        "/SourceFile:$BacpacPath"
        "/TargetServerName:$targetServer"
        "/TargetDatabaseName:$databaseName"
        "/AccessToken:$accessToken"
        '/TargetEncryptConnection:True'
        '/TargetTrustServerCertificate:False'
        '/TargetTimeout:60'
    )
    if ($databaseMode -eq 'azureSql') {
        $sqlPackageArguments += @(
            '/p:DatabaseEdition=Standard'
            '/p:DatabaseServiceObjective=S0'
            '/p:DatabaseMaximumSize=250'
        )
    }

    & $sqlPackagePath @sqlPackageArguments
    if ($LASTEXITCODE -ne 0) {
        throw "SqlPackage import failed with exit code $LASTEXITCODE."
    }
}
catch {
    $operationError = $_
}
finally {
    $accessToken = $null
    if ($ruleCreated) {
        if ($databaseMode -eq 'azureSql') {
            try {
                az sql server firewall-rule delete `
                    --resource-group $resourceGroupName `
                    --server $serverName `
                    --name $ruleName `
                    --output none
            }
            catch {
                Add-CleanupFailure `
                    -Failures $cleanupFailures `
                    -Action "Removing Azure SQL firewall rule '$ruleName'" `
                    -ErrorRecord $_
            }
        }
        else {
            try {
                az network nsg rule delete `
                    --resource-group $resourceGroupName `
                    --nsg-name ([string]$values['LAB04_SQL_MI_NSG_NAME']) `
                    --name $ruleName `
                    --output none
            }
            catch {
                Add-CleanupFailure `
                    -Failures $cleanupFailures `
                    -Action "Removing SQL MI NSG rule '$ruleName'" `
                    -ErrorRecord $_
            }
        }
    }

    if ($restoreAzureSqlPublicAccess) {
        try {
            az sql server update `
                --resource-group $resourceGroupName `
                --name $serverName `
                --enable-public-network false `
                --output none
        }
        catch {
            Add-CleanupFailure `
                -Failures $cleanupFailures `
                -Action "Restoring disabled public access on Azure SQL server '$serverName'" `
                -ErrorRecord $_
        }
    }
}

if ($operationError) {
    $message = "BACPAC import failed: $($operationError.Exception.Message)"
    if ($cleanupFailures.Count -gt 0) {
        $message += " Cleanup also failed: $($cleanupFailures -join '; ')"
    }
    throw $message
}
if ($cleanupFailures.Count -gt 0) {
    throw "BACPAC import completed, but temporary access cleanup failed: $($cleanupFailures -join '; ')"
}

Write-Host "Imported '$BacpacPath' as database '$databaseName' on '$serverName'."

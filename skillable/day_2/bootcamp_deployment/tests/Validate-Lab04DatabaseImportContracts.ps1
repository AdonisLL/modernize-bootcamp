[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Resolve-Path (Join-Path $projectRoot '..\..\..')
$helperPath = Join-Path $projectRoot 'assets\scripts\Lab04DatabaseImport.ps1'
$importScriptPath = Join-Path $projectRoot 'assets\scripts\Import-Lab04Database.ps1'
$postprovisionPath = Join-Path $projectRoot 'infra\hooks\postprovision.ps1'
$deployScriptPath = Join-Path $projectRoot 'infra\Deploy-Lab04.ps1'
$azureYamlPath = Join-Path $projectRoot 'azure.yaml'
$mainBicepPath = Join-Path $projectRoot 'infra\main.bicep'
$sqlDatabaseModulePath = Join-Path `
    $projectRoot `
    'infra\lab04\complete\modules\sql-database.bicep'
$sqlManagedInstanceModulePath = Join-Path `
    $projectRoot `
    'infra\lab04\complete\modules\sql-managed-instance.bicep'
$bacpacPath = Join-Path $repositoryRoot 'data\eshop.bacpac'

. $helperPath

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

foreach ($path in @(
    $helperPath,
    $importScriptPath,
    $postprovisionPath,
    $deployScriptPath
)) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $path,
        [ref]$tokens,
        [ref]$parseErrors
    )
    foreach ($parseError in $parseErrors) {
        $failures.Add("$path failed PowerShell parsing: $($parseError.Message)")
    }
}

Assert-Contract (Test-Path -LiteralPath $bacpacPath -PathType Leaf) `
    "The repository BACPAC is missing at '$bacpacPath'."
Assert-Contract (Test-Lab04PublicIPv4Address -IpAddress '203.0.113.10') `
    'A canonical public IPv4 address must be accepted.'
foreach ($invalidAddress in @(
    '203.0.113.010',
    '2001:db8::1',
    '203.0.113.10/32',
    'not-an-address'
)) {
    Assert-Contract (
        -not (Test-Lab04PublicIPv4Address -IpAddress $invalidAddress)
    ) "Invalid IPv4 input '$invalidAddress' must be rejected."
}

$ruleParameters = @{
    SubscriptionId = '11111111-1111-1111-1111-111111111111'
    EnvironmentName = 'lab04'
    DatabaseMode = 'sqlMi'
}
$ruleName = New-Lab04DatabaseImportRuleName @ruleParameters
Assert-Contract (
    $ruleName -eq (New-Lab04DatabaseImportRuleName @ruleParameters)
) 'Database import rule names must be deterministic.'
Assert-Contract ($ruleName -match '^AllowBacpacImport-[0-9a-f]{24}$') `
    'Database import rule names must use the bounded expected format.'
Assert-Contract (
    $ruleName -ne (
        New-Lab04DatabaseImportRuleName `
            -SubscriptionId $ruleParameters.SubscriptionId `
            -EnvironmentName $ruleParameters.EnvironmentName `
            -DatabaseMode azureSql
    )
) 'Azure SQL and SQL MI imports must use different rule names.'

Assert-Contract (
    (Get-Lab04SqlPackageVersion) -eq '170.5.96'
) 'SqlPackage must remain pinned to version 170.5.96.'
Assert-Contract (
    (Get-Lab04SqlPackageFeed) -eq 'https://api.nuget.org/v3/index.json'
) 'SqlPackage installation must use the expected explicit NuGet v3 feed.'
$expectedExecutableName = $IsWindows ? 'sqlpackage.exe' : 'sqlpackage'
Assert-Contract (
    (Get-Lab04SqlPackageExecutableName) -eq $expectedExecutableName
) 'SqlPackage executable resolution must match the current platform.'
$testProjectRoot = Join-Path ([IO.Path]::GetTempPath()) 'lab04-contract-root'
$expectedCachePath = Join-Path `
    $testProjectRoot `
    '.azure' `
    'tools' `
    'sqlpackage' `
    '170.5.96'
Assert-Contract (
    (Get-Lab04SqlPackageCachePath -ProjectRoot $testProjectRoot) -eq
        $expectedCachePath
) 'SqlPackage must use the versioned project-local .azure tools cache.'

$importCommand = Get-Command -Name $importScriptPath
$parameterSetNames = @($importCommand.ParameterSets.Name)
Assert-Contract ('Azd' -in $parameterSetNames) `
    'The importer must expose an Azd parameter set.'
Assert-Contract ('Arm' -in $parameterSetNames) `
    'The importer must expose an Arm parameter set.'

$azureYaml = Get-Content -LiteralPath $azureYamlPath -Raw
$postprovision = Get-Content -LiteralPath $postprovisionPath -Raw
$deployScript = Get-Content -LiteralPath $deployScriptPath -Raw
$helperScript = Get-Content -LiteralPath $helperPath -Raw
$importScript = Get-Content -LiteralPath $importScriptPath -Raw
Assert-Contract (
    $azureYaml -match '(?m)^\s*postprovision:\s*$' -and
    $azureYaml -match 'infra/hooks/postprovision\.ps1'
) 'azure.yaml must invoke the database import postprovision hook.'
Assert-Contract (
    $postprovision -match 'Import-Lab04Database\.ps1' -and
    $postprovision -match '-AzdEnvironment'
) 'The postprovision hook must invoke the shared importer with AZD outputs.'
Assert-Contract (
    $deployScript -match 'Import-Lab04Database\.ps1' -and
    $deployScript -match '-DeploymentName\s+\$armDeploymentName'
) 'The direct Deploy action must invoke the shared importer with ARM outputs.'
Assert-Contract (
    $helperScript -match 'dotnet tool install Microsoft\.SqlPackage' -and
    $helperScript -match '--tool-path\s+\$temporaryPath' -and
    $helperScript -match '--add-source\s+\$script:Lab04SqlPackageFeed' -and
    $helperScript -notmatch '(?m)(?:^|\s)(?:-g|--global)(?:\s|$)'
) 'SqlPackage must install into the local cache without global tool mutation.'
Assert-Contract (
    $importScript -notmatch 'Get-Command\s+[''"]?SqlPackage' -and
    $importScript -match 'Resolve-Lab04SqlPackage\s+-ProjectRoot\s+\$projectRoot' -and
    $importScript -match '&\s+\$sqlPackagePath\s+@sqlPackageArguments'
) 'The importer must resolve and invoke the project-local SqlPackage executable.'
$existingDatabaseCheckIndex = $importScript.IndexOf(
    'if ([int]$existingDatabaseCount -gt 0)'
)
$sqlPackageResolutionIndex = $importScript.IndexOf(
    '$sqlPackagePath = Resolve-Lab04SqlPackage'
)
Assert-Contract (
    $existingDatabaseCheckIndex -ge 0 -and
    $sqlPackageResolutionIndex -gt $existingDatabaseCheckIndex
) 'Existing databases must short-circuit before SqlPackage installation.'

$mainBicep = Get-Content -LiteralPath $mainBicepPath -Raw
$sqlDatabaseModule = Get-Content -LiteralPath $sqlDatabaseModulePath -Raw
$sqlManagedInstanceModule = Get-Content `
    -LiteralPath $sqlManagedInstanceModulePath `
    -Raw
Assert-Contract (
    $mainBicep -match "(?m)^var databaseName = 'eshop_ai'\r?$" -and
    $mainBicep -match '(?m)^output LAB04_DATABASE_NAME string = databaseName\r?$'
) 'The deployment database output must resolve to exact lowercase eshop_ai.'
Assert-Contract (
    $sqlDatabaseModule -notmatch "Microsoft\.Sql/servers/databases@"
) 'The Azure SQL module must not deploy an empty database resource.'
Assert-Contract (
    $sqlManagedInstanceModule -notmatch "Microsoft\.Sql/managedInstances/databases@"
) 'The SQL MI module must not deploy an empty managed database resource.'

if ($failures.Count -gt 0) {
    throw "Lab 04 database import validation failed:`n- $($failures -join "`n- ")"
}

Write-Host 'Lab 04 database import contracts are valid.'

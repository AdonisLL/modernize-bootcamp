[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SubscriptionId,

    [ValidateLength(1, 57)]
    [ValidatePattern('^[a-zA-Z0-9-]+$')]
    [string]$EnvironmentName = 'lab04-direct',

    [ValidateLength(1, 64)]
    [ValidatePattern('^[a-zA-Z0-9._()\-]+$')]
    [string]$DeploymentName,

    [ValidatePattern('^[a-z0-9]+$')]
    [string]$PrimaryLocation = 'centralus',

    [ValidatePattern('^[a-z0-9]+$')]
    [string]$DeploymentLocation = $PrimaryLocation,

    [ValidatePattern('^[a-z0-9]+$')]
    [string]$SecondaryLocation = 'centralus',

    [ValidatePattern('^[a-z0-9]+$')]
    [string]$ApplicationLocation = 'centralus',

    [ValidateLength(3, 18)]
    [ValidatePattern('(?-i)^(?!.*--)[a-z0-9][a-z0-9-]{1,16}[a-z0-9]$')]
    [string]$Prefix = 'caldova-lab04',

    [ValidateSet('azureSql', 'sqlMi')]
    [string]$DatabaseMode = 'sqlMi',

    [ValidateSet('Freemium', 'Regular')]
    [string]$SqlMiPricingModel = 'Freemium',

    [ValidateSet('Validate', 'WhatIf', 'Deploy')]
    [string]$Action = 'WhatIf',

    [string]$VmAdminUsername = 'labadmin',

    [securestring]$VmAdminPassword,

    [string]$SqlEntraAdminLogin
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

function Get-RequiredDeploymentOutput {
    param(
        [Parameter(Mandatory)][object]$Outputs,
        [Parameter(Mandatory)][string]$Name
    )

    $property = $Outputs.PSObject.Properties[$Name]
    $value = if ($property) {
        $property.Value.value
    }
    else {
        $null
    }
    if ([string]::IsNullOrWhiteSpace("$value")) {
        throw "Deployment output '$Name' was not returned."
    }

    return [string]$value
}

function Approve-FrontDoorPrivateLink {
    param(
        [Parameter(Mandatory)][string]$DeploymentName
    )

    $outputs = az deployment sub show `
        --name $DeploymentName `
        --query properties.outputs `
        --output json | ConvertFrom-Json

    $environmentId = Get-RequiredDeploymentOutput `
        -Outputs $outputs `
        -Name 'LAB04_CONTAINER_APPS_ENVIRONMENT_ID'
    $originId = Get-RequiredDeploymentOutput `
        -Outputs $outputs `
        -Name 'FRONT_DOOR_ORIGIN_ID'
    $requestMessage = Get-RequiredDeploymentOutput `
        -Outputs $outputs `
        -Name 'FRONT_DOOR_PRIVATE_LINK_REQUEST_MESSAGE'
    $endpointHostName = Get-RequiredDeploymentOutput `
        -Outputs $outputs `
        -Name 'FRONT_DOOR_ENDPOINT'

    $connectionApproved = $false
    for ($attempt = 1; $attempt -le 20; $attempt++) {
        $connections = @(
            az network private-endpoint-connection list `
                --id $environmentId `
                --output json | ConvertFrom-Json
        )

        $unknownPending = @(
            $connections | Where-Object {
                $_.properties.privateLinkServiceConnectionState.status -eq 'Pending' -and
                $_.properties.privateLinkServiceConnectionState.description -ne $requestMessage
            }
        )
        if ($unknownPending.Count -gt 0) {
            throw 'Unknown pending private endpoint connection detected. No connection was approved.'
        }

        $expectedConnections = @(
            $connections | Where-Object {
                $_.properties.privateLinkServiceConnectionState.description -eq $requestMessage -and
                $_.properties.privateLinkServiceConnectionState.status -in @('Pending', 'Approved')
            }
        )
        if ($expectedConnections.Count -gt 1) {
            throw 'Multiple private endpoint connections match the expected Front Door request.'
        }

        if ($expectedConnections.Count -eq 1) {
            $connection = $expectedConnections[0]
            if ($connection.properties.privateLinkServiceConnectionState.status -eq 'Pending') {
                az network private-endpoint-connection approve `
                    --id $connection.id `
                    --description $requestMessage `
                    --output none
            }

            $connectionStatus = az network private-endpoint-connection show `
                --id $connection.id `
                --query properties.privateLinkServiceConnectionState.status `
                --output tsv
            if ($connectionStatus -eq 'Approved') {
                $connectionApproved = $true
                break
            }
        }

        Start-Sleep -Seconds 15
    }

    if (-not $connectionApproved) {
        throw 'The expected Front Door Private Link request was not approved within five minutes.'
    }

    $originHostName = az resource show `
        --ids $originId `
        --api-version 2024-02-01 `
        --query properties.hostName `
        --output tsv
    if ([string]::IsNullOrWhiteSpace($originHostName)) {
        throw 'The expected Front Door origin could not be verified.'
    }

    $endpointReady = $false
    $endpointUri = "https://$endpointHostName/"
    for ($attempt = 1; $attempt -le 30; $attempt++) {
        try {
            $response = Invoke-WebRequest `
                -Uri $endpointUri `
                -Method Get `
                -TimeoutSec 30 `
                -SkipHttpErrorCheck
            if ([int]$response.StatusCode -ge 200 -and [int]$response.StatusCode -lt 400) {
                $endpointReady = $true
                break
            }
        }
        catch {
            if ($attempt -eq 30) {
                throw
            }
        }

        Start-Sleep -Seconds 20
    }

    if (-not $endpointReady) {
        throw "Front Door endpoint '$endpointUri' did not become healthy within ten minutes."
    }

    Write-Host "Front Door Private Link is approved and '$endpointUri' is ready."
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI 'az' was not found on PATH."
}

az account set --subscription $SubscriptionId

$tenantId = az account show --query tenantId --output tsv
if ($SqlEntraAdminLogin) {
    try {
        $sqlAdmin = az ad user show `
            --id $SqlEntraAdminLogin `
            --query '{id:id,login:userPrincipalName}' `
            --output json | ConvertFrom-Json
    }
    catch {
        throw "Unable to resolve SQL administrator '$SqlEntraAdminLogin' as a Microsoft Entra user. Verify the user principal name and reauthenticate interactively with 'az login --tenant $tenantId'."
    }
}
else {
    try {
        $sqlAdmin = az ad signed-in-user show `
            --query '{id:id,login:userPrincipalName}' `
            --output json | ConvertFrom-Json
    }
    catch {
        throw "Unable to resolve the signed-in Microsoft Entra user. Reauthenticate interactively with 'az login --tenant $tenantId', or supply -SqlEntraAdminLogin with a user principal name."
    }
}

if (-not $sqlAdmin.id -or -not $sqlAdmin.login) {
    throw 'The selected Microsoft Entra SQL administrator did not return both an object ID and user principal name.'
}

$SqlEntraAdminObjectId = [string]$sqlAdmin.id
$SqlEntraAdminLogin = [string]$sqlAdmin.login
$parsedObjectId = [guid]::Empty
if (-not [guid]::TryParse($SqlEntraAdminObjectId, [ref]$parsedObjectId)) {
    throw "The resolved SQL administrator object ID must be a GUID. Received '$SqlEntraAdminObjectId'."
}

if (-not $VmAdminPassword) {
    $VmAdminPassword = Read-Host 'Enter a strong VM administrator password' -AsSecureString
}

$plainTextPassword = [Net.NetworkCredential]::new('', $VmAdminPassword).Password
if (
    $plainTextPassword.Length -lt 12 -or
    $plainTextPassword.Length -gt 72 -or
    $plainTextPassword -notmatch '[a-z]' -or
    $plainTextPassword -notmatch '[A-Z]' -or
    $plainTextPassword -notmatch '[0-9]' -or
    $plainTextPassword -notmatch '[!@$%*_\-+=]' -or
    $plainTextPassword -notmatch '^[a-zA-Z0-9!@$%*_\-+=]+$' -or
    $plainTextPassword.IndexOf(
        $VmAdminUsername,
        [StringComparison]::OrdinalIgnoreCase
    ) -ge 0
) {
    $plainTextPassword = $null
    throw 'The VM password must be 12-72 characters, exclude the username, and contain lowercase, uppercase, numeric, and ! @ $ % * _ - + = characters only.'
}

$templateFile = Join-Path $PSScriptRoot 'main.bicep'
$armDeploymentName = if ($DeploymentName) {
    $DeploymentName
}
else {
    "$EnvironmentName-deploy"
}
$deploymentParameters = @(
    "environmentName=$EnvironmentName"
    "primaryLocation=$PrimaryLocation"
    "secondaryLocation=$SecondaryLocation"
    "applicationLocation=$ApplicationLocation"
    "prefix=$Prefix"
    "databaseMode=$DatabaseMode"
    "sqlMiPricingModel=$SqlMiPricingModel"
    "sqlEntraAdminObjectId=$SqlEntraAdminObjectId"
    "sqlEntraAdminLogin=$SqlEntraAdminLogin"
    "vmAdminUsername=$VmAdminUsername"
    "vmAdminPassword=$plainTextPassword"
)

try {
    $deploymentCommand = switch ($Action) {
        'Validate' { 'validate' }
        'WhatIf' { 'what-if' }
        'Deploy' { 'create' }
    }
    $arguments = @(
        'deployment'
        'sub'
        $deploymentCommand
        '--name'
        $armDeploymentName
        '--location'
        $DeploymentLocation
        '--template-file'
        $templateFile
        '--parameters'
    ) + $deploymentParameters
    if ($Action -eq 'Deploy') {
        $arguments += '--confirm-with-what-if'
    }

    & az @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Azure deployment action '$Action' failed with exit code $LASTEXITCODE."
    }

    if ($Action -eq 'Deploy') {
        Approve-FrontDoorPrivateLink -DeploymentName $armDeploymentName
        $importScriptPath = Join-Path `
            (Split-Path -Parent $PSScriptRoot) `
            'assets\scripts\Import-Lab04Database.ps1'
        & $importScriptPath -DeploymentName $armDeploymentName

        $configureScriptPath = Join-Path `
            (Split-Path -Parent $PSScriptRoot) `
            'assets\scripts\Configure-Lab04GitHub.ps1'
        Write-Host ''
        Write-Host "Subscription deployment name: $armDeploymentName"
        Write-Host 'Optional GitHub OIDC setup (run from this Git checkout):'
        Write-Host "& '$configureScriptPath' -SubscriptionId '$SubscriptionId' -DeploymentName '$armDeploymentName' -RequiredReviewer '<github-user-login>' -DeploymentBranch 'main'"
    }
}
finally {
    $plainTextPassword = $null
}

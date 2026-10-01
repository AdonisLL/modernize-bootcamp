Set-StrictMode -Version Latest

$script:Lab04SqlPackageVersion = '170.5.96'
$script:Lab04SqlPackageFeed = 'https://api.nuget.org/v3/index.json'

function Test-Lab04PublicIPv4Address {
    param([Parameter(Mandatory)][string]$IpAddress)

    $parsedAddress = $null
    return (
        [Net.IPAddress]::TryParse($IpAddress, [ref]$parsedAddress) -and
        $parsedAddress.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork -and
        $parsedAddress.ToString() -eq $IpAddress
    )
}

function New-Lab04DatabaseImportRuleName {
    param(
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$EnvironmentName,
        [Parameter(Mandatory)][ValidateSet('azureSql', 'sqlMi')][string]$DatabaseMode
    )

    $value = "$SubscriptionId|$EnvironmentName|$DatabaseMode".ToLowerInvariant()
    $bytes = [Text.Encoding]::UTF8.GetBytes($value)
    $hash = [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData($bytes)
    ).ToLowerInvariant()
    return "AllowBacpacImport-$($hash.Substring(0, 24))"
}

function Get-Lab04SqlPackageVersion {
    return $script:Lab04SqlPackageVersion
}

function Get-Lab04SqlPackageFeed {
    return $script:Lab04SqlPackageFeed
}

function Get-Lab04SqlPackageExecutableName {
    return $IsWindows ? 'sqlpackage.exe' : 'sqlpackage'
}

function Get-Lab04SqlPackageCachePath {
    param([Parameter(Mandatory)][string]$ProjectRoot)

    $toolsRoot = Join-Path `
        $ProjectRoot `
        '.azure' `
        'tools' `
        'sqlpackage'
    return Join-Path $toolsRoot $script:Lab04SqlPackageVersion
}

function Assert-Lab04SqlPackageVersion {
    param([Parameter(Mandatory)][string]$ExecutablePath)

    if (-not (Test-Path -LiteralPath $ExecutablePath -PathType Leaf)) {
        throw "SqlPackage executable was not found at '$ExecutablePath'."
    }

    $reportedVersion = (& $ExecutablePath /Version).ToString().Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "SqlPackage at '$ExecutablePath' failed its version check with exit code $LASTEXITCODE."
    }
    if ($reportedVersion -notmatch "^$([regex]::Escape($script:Lab04SqlPackageVersion))(?:\.0)?$") {
        throw "SqlPackage at '$ExecutablePath' reported version '$reportedVersion'; expected '$script:Lab04SqlPackageVersion'."
    }
}

function Resolve-Lab04SqlPackage {
    param([Parameter(Mandatory)][string]$ProjectRoot)

    $cachePath = Get-Lab04SqlPackageCachePath -ProjectRoot $ProjectRoot
    $executableName = Get-Lab04SqlPackageExecutableName
    $executablePath = Join-Path $cachePath $executableName
    if (Test-Path -LiteralPath $executablePath -PathType Leaf) {
        Assert-Lab04SqlPackageVersion -ExecutablePath $executablePath
        return $executablePath
    }
    if (Test-Path -LiteralPath $cachePath) {
        throw "The SqlPackage cache at '$cachePath' is incomplete. Remove that version directory and rerun the deployment."
    }
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        throw "Required command 'dotnet' was not found on PATH. Install the .NET SDK and rerun the deployment."
    }

    $toolsRoot = Split-Path -Parent $cachePath
    $null = New-Item -ItemType Directory -Path $toolsRoot -Force
    $temporaryPath = Join-Path `
        $toolsRoot `
        ".install-$([guid]::NewGuid().ToString('N'))"

    try {
        & dotnet tool install Microsoft.SqlPackage `
            --tool-path $temporaryPath `
            --version $script:Lab04SqlPackageVersion `
            --add-source $script:Lab04SqlPackageFeed `
            --ignore-failed-sources `
            --allow-roll-forward | Write-Host
        if ($LASTEXITCODE -ne 0) {
            throw "Installing Microsoft.SqlPackage $script:Lab04SqlPackageVersion failed with exit code $LASTEXITCODE."
        }

        $temporaryExecutablePath = Join-Path $temporaryPath $executableName
        Assert-Lab04SqlPackageVersion `
            -ExecutablePath $temporaryExecutablePath

        if (Test-Path -LiteralPath $cachePath) {
            if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
                throw "Another SqlPackage installation created an incomplete cache at '$cachePath'."
            }
            Assert-Lab04SqlPackageVersion -ExecutablePath $executablePath
            return $executablePath
        }

        try {
            Move-Item -LiteralPath $temporaryPath -Destination $cachePath
        }
        catch {
            if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
                throw
            }
            Assert-Lab04SqlPackageVersion -ExecutablePath $executablePath
            return $executablePath
        }
        Assert-Lab04SqlPackageVersion -ExecutablePath $executablePath
        return $executablePath
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Recurse -Force
        }
    }
}

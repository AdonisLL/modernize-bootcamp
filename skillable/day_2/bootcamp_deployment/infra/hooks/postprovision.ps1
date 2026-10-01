[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

if (-not (Get-Command azd -ErrorAction SilentlyContinue)) {
    throw "Required command 'azd' was not found on PATH."
}

$environmentName = (azd env get-value AZURE_ENV_NAME).Trim()
if ([string]::IsNullOrWhiteSpace($environmentName)) {
    throw 'The active AZD environment did not return AZURE_ENV_NAME.'
}

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$importScriptPath = Join-Path `
    $projectRoot `
    'assets\scripts\Import-Lab04Database.ps1'

& $importScriptPath -AzdEnvironment $environmentName

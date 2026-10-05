# Downloads the latest BcContainerHelper from PSGallery into .\Modules of this folder - no admin, and no Documents folder
# (Install-Module -Scope CurrentUser may fail there, e.g. with Controlled Folder Access). Run again to update it.
$ErrorActionPreference = 'Stop'
# Windows PowerShell 5.1 started from a PowerShell 7 session inherits the PowerShell 7 module path - reset it
$env:PSModulePath = @(
    (Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules'),
    (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\Modules')
) -join ';'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Import-Module PowerShellGet
$target = Join-Path $PSScriptRoot 'Modules'
New-Item -ItemType Directory -Path $target -Force | Out-Null
Save-Module -Name BcContainerHelper -Repository PSGallery -Path $target -Force
Get-ChildItem (Join-Path $target 'BcContainerHelper') | ForEach-Object { "BcContainerHelper $($_.Name)" }

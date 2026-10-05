# Dot-source from the other scripts: . "$PSScriptRoot\Import-Helper.ps1"
# Imports BcContainerHelper from .\Modules (Install-Helper.ps1), reads .\settings.json and provides the container
# credential and the start of Docker and the container.
$ErrorActionPreference = 'Stop'
# Windows PowerShell 5.1 started from a PowerShell 7 session inherits the PowerShell 7 module path (PowerShellGet,
# Microsoft.PowerShell.Security... built for .NET Core then fail to load) - reset it to the 5.1 defaults
$env:PSModulePath = @(
    (Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules'),
    (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\Modules')
) -join ';'

# Defaults, overridden by settings.json next to the scripts (written by SETUP.md, step 9)
$TestContainerSettings = [ordered]@{
    containerName  = 'bctest28'
    version        = '28.4'
    country        = 'cz'
    memoryLimit    = '8G'
    patFile        = Join-Path (Split-Path $PSScriptRoot -Parent) 'MCP_PAT\DevOpsPAT.txt'
    nuGetServerUrl = 'https://pkgs.dev.azure.com/essencebs/Projects/_packaging/BCNugetPackages/nuget/v3/index.json'
}
$settingsFile = Join-Path $PSScriptRoot 'settings.json'
if (Test-Path $settingsFile) {
    $settings = [System.IO.File]::ReadAllText($settingsFile) | ConvertFrom-Json
    foreach ($property in $settings.PSObject.Properties) {
        if ($TestContainerSettings.Contains($property.Name)) { $TestContainerSettings[$property.Name] = "$($property.Value)" }
    }
}

$helperManifest = Get-ChildItem (Join-Path $PSScriptRoot 'Modules\BcContainerHelper') -Directory -ErrorAction SilentlyContinue |
    Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1 |
    ForEach-Object { Join-Path $_.FullName 'BcContainerHelper.psd1' }
if (-not $helperManifest) { throw 'BcContainerHelper not found in .\Modules - run Install-Helper.ps1 first.' }
Import-Module $helperManifest -Force -DisableNameChecking

$CredentialFile = Join-Path $PSScriptRoot 'credential.xml'

function Get-TestContainerCredential {
    # The admin user of the test containers. Created on first use with a random password; saved with DPAPI
    # (Export-Clixml), so only this Windows user on this machine can read it.
    if (-not (Test-Path $CredentialFile)) {
        $chars = [char[]]'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
        $bytes = New-Object byte[] 20
        [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
        $password = (-join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })) + '!7a'
        $credential = New-Object pscredential 'admin', (ConvertTo-SecureString $password -AsPlainText -Force)
        $credential | Export-Clixml -Path $CredentialFile
    }
    Import-Clixml -Path $CredentialFile
}

function Invoke-Docker {
    # docker writes its errors to stderr - with ErrorActionPreference Stop, Windows PowerShell 5.1 would throw on them
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $output = & docker @args 2>&1 | ForEach-Object { "$_" } } finally { $ErrorActionPreference = $previous }
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
}

function Start-TestContainer([string] $ContainerName) {
    # Docker Desktop in the Windows containers mode, then the container itself - both may be stopped after a restart
    $engine = Invoke-Docker version --format '{{.Server.Os}}'
    if ($engine.ExitCode -ne 0) {
        $dockerDesktop = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
        Write-Host 'Starting Docker Desktop'
        Start-Process -FilePath $dockerDesktop
        $deadline = (Get-Date).AddMinutes(4)
        do {
            Start-Sleep -Seconds 5
            $engine = Invoke-Docker version --format '{{.Server.Os}}'
        } until (($engine.ExitCode -eq 0) -or ((Get-Date) -gt $deadline))
        if ($engine.ExitCode -ne 0) { throw "Docker engine does not answer: $($engine.Output)" }
    }
    if ($engine.Output.Trim() -ne 'windows') {
        Write-Host 'Switching Docker Desktop to Windows containers'
        & (Join-Path $env:ProgramFiles 'Docker\Docker\DockerCli.exe') -SwitchWindowsEngine
        Start-Sleep -Seconds 15
    }
    $state = Invoke-Docker inspect -f '{{.State.Running}}' $ContainerName
    if ($state.ExitCode -ne 0) { throw "Container $ContainerName does not exist - create it with New-TestContainer.ps1." }
    if ($state.Output.Trim() -ne 'true') {
        Write-Host "Starting container $ContainerName"
        Start-BcContainer -containerName $ContainerName
    }
}

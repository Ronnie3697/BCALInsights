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
    # The pool Test-Repo.ps1 takes a free container from; empty = containerName only
    containerNames = @()
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
        if (-not $TestContainerSettings.Contains($property.Name)) { continue }
        if ($property.Value -is [array]) { $TestContainerSettings[$property.Name] = @($property.Value | ForEach-Object { "$_" }) }
        else { $TestContainerSettings[$property.Name] = "$($property.Value)" }
    }
}
if (@($TestContainerSettings.containerNames).Count -eq 0) { $TestContainerSettings.containerNames = @($TestContainerSettings.containerName) }

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

function Lock-TestContainer([string[]] $ContainerNames, [string] $RunName, [int] $PollSeconds = 15) {
    # Takes the run lock of the first free container of the pool and returns it ({ ContainerName, Stream }); waits while
    # all of them are busy. The lock is a file kept open without sharing - a run that dies (crash, closed window) releases
    # it with its process, no stale lock. Release it with Unlock-TestContainer. Next to it test-run.owner says who holds
    # it, for the message of a waiting run.
    $announced = $false
    while ($true) {
        foreach ($name in $ContainerNames) {
            $folder = Join-Path $bcContainerHelperConfig.hostHelperFolder "Extensions\$name"
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
            try {
                $stream = [System.IO.File]::Open((Join-Path $folder 'test-run.lock'), [System.IO.FileMode]::OpenOrCreate,
                    [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            }
            catch {
                # Held by another run (sharing violation) - try the next container; any other error is a real one
                if (($_.Exception -is [System.IO.IOException]) -or ($_.Exception.InnerException -is [System.IO.IOException])) { continue }
                throw
            }
            Set-Content -Path (Join-Path $folder 'test-run.owner') -Value ('{0} (PID {1}, since {2:HH:mm:ss})' -f $RunName, $PID, (Get-Date))
            return [pscustomobject]@{ ContainerName = $name; Stream = $stream }
        }
        if (-not $announced) {
            $owners = foreach ($name in $ContainerNames) {
                $ownerFile = Join-Path $bcContainerHelperConfig.hostHelperFolder "Extensions\$name\test-run.owner"
                '{0}: {1}' -f $name, $(if (Test-Path $ownerFile) { (Get-Content -Path $ownerFile -Raw).Trim() } else { '?' })
            }
            Write-Host ('All test containers are busy - waiting for a free one ({0})' -f ($owners -join '; '))
            $announced = $true
        }
        Start-Sleep -Seconds $PollSeconds
    }
}

function Unlock-TestContainer($Lock) {
    if ($Lock -and $Lock.Stream) { $Lock.Stream.Dispose() }
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
    # Right after a Docker Desktop start the container is "running" again (restart policy), but the BC service inside is
    # still starting - the first docker exec then fails ("No such exec instance"). Wait for the health check.
    $deadline = (Get-Date).AddMinutes(10)
    do {
        $health = (Invoke-Docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' $ContainerName).Output.Trim()
        if (($health -eq 'healthy') -or ($health -eq 'none')) { return }
        Write-Host "Waiting for container $ContainerName ($health)"
        Start-Sleep -Seconds 10
    } until ((Get-Date) -gt $deadline)
    throw "Container $ContainerName is not healthy after 10 minutes ($health)."
}

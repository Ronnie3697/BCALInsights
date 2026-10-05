# Creates the shared local test container: BC OnPrem with the test toolkit (Test Runner, test framework, test
# libraries), no apps of ours. The repos are published into it, tested and removed again by Test-Repo.ps1.
# Defaults from settings.json (container bctest28, BC 28.4 cz, 8G): 28.4 is closer to the SaaS customers than the
# pipelines (BC_ARTIFACT 28.0-28.3); the apps declare application 28.0.0.0, so they all run on it.
# The first run downloads the artifacts and the generic image - about 25 minutes.
Param(
    [string] $ContainerName = '',
    [string] $Version = '',
    [string] $Country = '',
    [string] $MemoryLimit = ''
)
. (Join-Path $PSScriptRoot 'Import-Helper.ps1')
if (-not $ContainerName) { $ContainerName = $TestContainerSettings.containerName }
if (-not $Version) { $Version = $TestContainerSettings.version }
if (-not $Country) { $Country = $TestContainerSettings.country }
if (-not $MemoryLimit) { $MemoryLimit = $TestContainerSettings.memoryLimit }

$artifactUrl = Get-BcArtifactUrl -type OnPrem -version $Version -country $Country -select Latest
if (-not $artifactUrl) { throw "No OnPrem artifact for $Version/$Country" }
Write-Host "Artifact: $artifactUrl"

New-BcContainer `
    -accept_eula `
    -containerName $ContainerName `
    -artifactUrl $artifactUrl `
    -auth NavUserPassword `
    -Credential (Get-TestContainerCredential) `
    -includeTestToolkit `
    -includeTestLibrariesOnly `
    -memoryLimit $MemoryLimit `
    -shortcuts None

Write-Host "Container $ContainerName is ready."

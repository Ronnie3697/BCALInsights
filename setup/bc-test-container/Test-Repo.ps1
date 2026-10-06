# Publishes the apps of an AL repo into the shared test container, runs the tests of its test apps and removes the
# apps again - the way the Essence pipeline does it: dependencies from BCNugetPackages (latest in the MajorMinor range of
# the declared minimum, transitive ones from the .nuspec), apps compiled and installed in dependency order, test apps =
# apps with "Test" in the name. Starts Docker Desktop and the container when they are stopped. A repo without a test app
# ends right away.
#
# The dependencies stay PUBLISHED (not installed) for the next run: each run checks the version on the feed, installs the
# published one when it is the latest and publishes a newer one otherwise. Not installed, they run no code during the
# tests of another repo. The steps inside the container run in three sessions (ContainerSide.ps1).
#
#   .\Test-Repo.ps1 -RepoPath C:\WorkTasks\prod-ess-configurator-bc
#   .\Test-Repo.ps1 -RepoPath C:\WorkTasks\prod-ess-configurator-bc -TestCodeunit 63173
#   .\Test-Repo.ps1 -RepoPath C:\WorkTasks\cust-zlomek-bc -KeepApps
#
# The repo is not touched: the app folders are copied into the folder shared with the container and compiled there.
# Exit code 0 = all tests passed (or no test app), 1 = a test failed or the run broke.
Param(
    [Parameter(Mandatory = $true)]
    [string] $RepoPath,
    [string] $ContainerName = '',
    # Test codeunit ID or name filter (Run-TestsInBcContainer -testCodeunit), e.g. 63173 or 'Var. Config*'
    [string] $TestCodeunit = '*',
    [string] $TestFunction = '*',
    # Leave the apps installed after the run - for a rerun of single tests or a look into the container
    [switch] $KeepApps
)
. (Join-Path $PSScriptRoot 'Import-Helper.ps1')
if (-not $ContainerName) { $ContainerName = $TestContainerSettings.containerName }

$RepoPath = (Resolve-Path $RepoPath).Path.TrimEnd('\')

# --- Apps of the repo, in dependency order ------------------------------------------------------------------------
$excluded = '\\(\.alpackages|\.git|node_modules|\.snapshots|\.output|output|\.vscode)(\\|$)'
$appFolders = @(Get-ChildItem -Path $RepoPath -Filter 'app.json' -Recurse -Depth 3 -File |
    Where-Object { $_.DirectoryName -notmatch $excluded } |
    Where-Object { Get-ChildItem -Path $_.DirectoryName -Filter '*.al' -Recurse -File | Select-Object -First 1 } |
    ForEach-Object { $_.DirectoryName.Substring($RepoPath.Length).TrimStart('\') })
if ($appFolders.Count -eq 0) { throw "No AL app found in $RepoPath" }
$sortedFolders = @(Sort-AppFoldersByDependencies -appFolders $appFolders -baseFolder $RepoPath -WarningAction SilentlyContinue)
$apps = @(foreach ($folder in $sortedFolders) {
    $json = [System.IO.File]::ReadAllText((Join-Path $RepoPath "$folder\app.json")) | ConvertFrom-Json
    [pscustomobject]@{
        Folder       = $folder
        Id           = "$($json.id)".ToLowerInvariant()
        Name         = $json.name
        Publisher    = $json.publisher
        IsTest       = $json.name -match 'Test'
        Dependencies = @($json.dependencies | Where-Object { $_ })
    }
})
Write-Host 'Apps in dependency order:'
$apps | ForEach-Object { Write-Host ('  {0}{1}  ({2})' -f $_.Name, $(if ($_.IsTest) { ' [test]' } else { '' }), $_.Folder) }
if (-not ($apps | Where-Object { $_.IsTest })) {
    Write-Host 'SUMMARY: the repo has no test app (no "Test" in an app name) - nothing to run.'
    exit 0
}
$repoIds = @($apps | ForEach-Object { $_.Id })

$repoName = Split-Path $RepoPath -Leaf
$runName = '{0}-{1}' -f $repoName, (Get-Date -Format 'yyyyMMdd-HHmmss')
$runFolder = Join-Path $bcContainerHelperConfig.hostHelperFolder "Extensions\$ContainerName\test-runs\$runName"
$srcFolder = Join-Path $runFolder 'src'
$symbolsFolder = Join-Path $runFolder 'symbols'
$outputFolder = Join-Path $runFolder 'output'
$junitFile = Join-Path $runFolder 'TestResults.xml'
New-Item -ItemType Directory -Path $srcFolder, $symbolsFolder, $outputFolder -Force | Out-Null
Start-Transcript -Path (Join-Path $runFolder 'run.log') | Out-Null
Copy-Item -Path (Join-Path $PSScriptRoot 'ContainerSide.ps1') -Destination $runFolder

function Get-DependencyId($dependency) {
    if ($dependency.PSObject.Properties.Name -contains 'id') { return "$($dependency.id)".ToLowerInvariant() }
    return "$($dependency.appId)".ToLowerInvariant()
}

function Get-MajorMinorRange([version] $minimum) {
    # The pipeline: the latest version in the MajorMinor range of the declared minimum
    '[{0},{1}.{2}.0.0)' -f $minimum, $minimum.Major, ($minimum.Minor + 1)
}

# appId -> app file in the symbols folder, dependencies before the apps that need them
$dependencyFiles = [ordered]@{}
# Packages taken from the feed, by package id and version - kept between the runs
$dependencyCache = Join-Path $bcContainerHelperConfig.hostHelperFolder "Extensions\$ContainerName\dependency-cache"
# appId -> name filter of a Microsoft app the container must have installed
$microsoftApps = @{}

function Resolve-NuGetDependency([string] $packageId, [version] $minimum) {
    # Finds the latest version in the range on the feed, takes the package from the cache of the container (downloads
    # it only when a new version came out) and resolves the dependencies of its .nuspec first
    $appId = ($packageId -split '\.')[-1].ToLowerInvariant()
    if ($dependencyFiles.Contains($appId)) { return }
    $range = Get-MajorMinorRange $minimum
    $found = @(Find-BcNuGetPackage -nuGetServerUrl $TestContainerSettings.nuGetServerUrl -nuGetToken $nuGetToken -packageName $packageId -version $range -select Latest)
    if ($found.Count -lt 3 -or -not $found[1]) { throw "Package $packageId $range is not on $($TestContainerSettings.nuGetServerUrl)" }
    $foundId = $found[1]
    $foundVersion = $found[2]
    $packageCache = Join-Path $dependencyCache $foundId
    $packageFolder = Join-Path $packageCache $foundVersion
    if (Get-ChildItem -Path $packageFolder -Filter '*.app' -ErrorAction SilentlyContinue) {
        Write-Host "Dependency $foundId $foundVersion (range $range) - cached"
    }
    else {
        Write-Host "Dependency $foundId $foundVersion (range $range) - downloading"
        # Get-BcNuGetPackage extracts into a new temp folder on every call - kept in the cache of the container instead
        $downloaded = @(Get-BcNuGetPackage -nuGetServerUrl $TestContainerSettings.nuGetServerUrl -nuGetToken $nuGetToken -packageName $foundId -version $foundVersion -select Exact)[-1]
        Remove-Item -Path $packageCache -Recurse -Force -ErrorAction SilentlyContinue   # older versions
        New-Item -ItemType Directory -Path $packageFolder -Force | Out-Null
        Copy-Item -Path (Join-Path $downloaded '*.app'), (Join-Path $downloaded '*.nuspec') -Destination $packageFolder
        Remove-Item -Path $downloaded -Recurse -Force -ErrorAction SilentlyContinue
    }
    $nuspecFile = Get-ChildItem -Path $packageFolder -Filter '*.nuspec' | Select-Object -First 1
    if ($nuspecFile) {
        [xml]$nuspec = [System.IO.File]::ReadAllText($nuspecFile.FullName)
        foreach ($node in @($nuspec.SelectNodes("//*[local-name()='dependency']"))) {
            $dependencyPackageId = $node.GetAttribute('id')
            if ($dependencyPackageId -match '^Microsoft\.(.+)\.([0-9a-fA-F]{8}-[0-9a-fA-F-]{27})$') {
                $microsoftApps[$Matches[2].ToLowerInvariant()] = $Matches[1]
                continue
            }
            if ($dependencyPackageId -like 'Microsoft.*') { continue }   # Microsoft.Application / Microsoft.Platform
            $minimumText = [regex]::Match($node.GetAttribute('version'), '\d+(\.\d+){1,3}').Value
            Resolve-NuGetDependency -packageId $dependencyPackageId -minimum ([version]$minimumText)
        }
    }
    $appFile = Get-ChildItem -Path $packageFolder -Filter '*.app' | Select-Object -First 1
    if (-not $appFile) { throw "Package $foundId $foundVersion has no .app file" }
    Copy-Item -Path $appFile.FullName -Destination $symbolsFolder -Force
    $dependencyFiles[$appId] = Join-Path $symbolsFolder $appFile.Name
}

$allPassed = $false
# Installed apps (not Microsoft) this run found and did not install - the cleanup leaves them alone; $null = not prepared yet
$keepIds = $null
# Seconds per phase, printed at the end (TIMING)
$phaseSeconds = [ordered]@{ 'start' = 0.0; 'dependencies' = 0.0; 'compile' = 0.0; 'publish' = 0.0; 'tests' = 0.0; 'cleanup' = 0.0 }
$totalTimer = [System.Diagnostics.Stopwatch]::StartNew()
$phaseTimer = [System.Diagnostics.Stopwatch]::StartNew()
try {
    Start-TestContainer -ContainerName $ContainerName
    # Only after the start - Get-BcContainerPath reads the shared folders of the container from the Docker engine
    $containerSide = Get-BcContainerPath -containerName $ContainerName -path (Join-Path $runFolder 'ContainerSide.ps1')
    $credential = Get-TestContainerCredential
    if (-not (Test-Path $TestContainerSettings.patFile)) { throw "PAT file $($TestContainerSettings.patFile) not found (settings.json, patFile)." }
    $nuGetToken = (Get-Content -Path $TestContainerSettings.patFile -Raw).Trim()
    $phaseSeconds['start'] += $phaseTimer.Elapsed.TotalSeconds
    $phaseTimer.Restart()

    # --- Dependencies: versions from the feed (host), then one container session ------------------------------------
    foreach ($app in $apps) {
        foreach ($dependency in $app.Dependencies) {
            $dependencyId = Get-DependencyId $dependency
            if ($repoIds -contains $dependencyId) { continue }
            if ($dependency.publisher -eq 'Microsoft') {
                $microsoftApps[$dependencyId] = $dependency.name
                continue
            }
            $packageId = Get-BcNuGetPackageId -publisher $dependency.publisher -name $dependency.name -id $dependencyId
            Resolve-NuGetDependency -packageId $packageId -minimum ([version]$dependency.version)
        }
    }
    $containerFiles = @($dependencyFiles.Values | ForEach-Object { Get-BcContainerPath -containerName $ContainerName -path $_ })
    $microsoftList = @($microsoftApps.GetEnumerator() | ForEach-Object { "$($_.Key)|$($_.Value)" })
    # Session 1: clean slate - the apps of this repo left by an earlier run, all versions (e.g. a published dependency of
    # another repo) - and the installed apps of another run (-KeepApps), which the cleanup leaves as they are
    $snapshot = @(Invoke-ScriptInBcContainer -containerName $ContainerName -argumentList $containerSide, $repoIds -scriptblock {
        Param([string] $containerSide, [string[]] $repoIds)
        . $containerSide
        $leftovers = @(Get-NAVAppInfo -ServerInstance $ServerInstance -Tenant default -TenantSpecificProperties | Where-Object { $repoIds -contains "$($_.AppId)" })
        Remove-TestApps -Apps $leftovers -Unpublish
        Get-NAVAppInfo -ServerInstance $ServerInstance -Tenant default -TenantSpecificProperties |
            Where-Object { $_.IsInstalled -and ($_.Publisher -ne 'Microsoft') } | ForEach-Object { "KEEP:$($_.AppId):$($_.Name) $($_.Version)" }
    })
    $keepIds = @($snapshot | Where-Object { "$_" -like 'KEEP:*' } | ForEach-Object { ("$_" -split ':')[1] })
    $kept = @($snapshot | Where-Object { "$_" -like 'KEEP:*' } | ForEach-Object { ("$_" -split ':', 3)[2] })
    if ($kept) { Write-Warning ('The container has apps installed by another run: {0} - remove them if they collide (object IDs).' -f ($kept -join ', ')) }
    # Session 2: missing Microsoft apps from the artifact, then the dependencies - published only when not there yet
    Invoke-ScriptInBcContainer -containerName $ContainerName -argumentList $containerSide, $microsoftList, $containerFiles -scriptblock {
        Param([string] $containerSide, [string[]] $microsoftList, [string[]] $files)
        . $containerSide
        $installed = @(Get-NAVAppInfo -ServerInstance $ServerInstance -Tenant default -TenantSpecificProperties | Where-Object { $_.IsInstalled } | ForEach-Object { "$($_.AppId)" })
        foreach ($entry in $microsoftList) {
            $id, $name = $entry -split '\|', 2
            if ($installed -notcontains $id) { Install-MicrosoftAppFromArtifact -AppId $id -NameFilter $name | Out-Null }
        }
        Install-TestAppFiles -Files $files | Out-Null
    }
    $phaseSeconds['dependencies'] += $phaseTimer.Elapsed.TotalSeconds
    $phaseTimer.Restart()

    # --- Compile the apps of the repo (copies in the shared folder), then install them in one session ---------------------
    foreach ($app in $apps) {
        $source = Join-Path $RepoPath $app.Folder
        $target = Join-Path $srcFolder $app.Folder
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        # robocopy: exit codes below 8 are success
        robocopy $source $target /E /NFL /NDL /NJH /NJS /NP /XD .alpackages .output output .snapshots .git /XF *.app | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "Copying $source failed (robocopy $LASTEXITCODE)" }
    }
    $compiledFiles = @()
    foreach ($app in $apps) {
        Write-Host "Compiling $($app.Name)"
        $appFile = Compile-AppInBcContainer -containerName $ContainerName -credential $credential `
            -appProjectFolder (Join-Path $srcFolder $app.Folder) -appOutputFolder $outputFolder -appSymbolsFolder $symbolsFolder `
            -CopyAppToSymbolsFolder -basePath $srcFolder
        $compiledFiles += Get-BcContainerPath -containerName $ContainerName -path $appFile
    }
    $phaseSeconds['compile'] += $phaseTimer.Elapsed.TotalSeconds
    $phaseTimer.Restart()
    Invoke-ScriptInBcContainer -containerName $ContainerName -argumentList $containerSide, $compiledFiles -scriptblock {
        Param([string] $containerSide, [string[]] $files)
        . $containerSide
        Install-TestAppFiles -Files $files -SyncMode ForceSync | Out-Null
    }
    $phaseSeconds['publish'] += $phaseTimer.Elapsed.TotalSeconds
    $phaseTimer.Restart()

    # --- Tests --------------------------------------------------------------------------------------------------------
    $allPassed = $true
    $append = $false
    foreach ($testApp in @($apps | Where-Object { $_.IsTest })) {
        Write-Host "Running tests of $($testApp.Name) (codeunit $TestCodeunit, function $TestFunction)"
        $passed = Run-TestsInBcContainer -containerName $ContainerName -credential $credential -extensionId $testApp.Id `
            -testCodeunit $TestCodeunit -testFunction $TestFunction -detailed -returnTrueIfAllPassed `
            -JUnitResultFileName $junitFile -AppendToJUnitResultFile:$append
        $append = $true
        if (-not $passed) { $allPassed = $false }
    }
    $phaseSeconds['tests'] += $phaseTimer.Elapsed.TotalSeconds

    # --- Summary --------------------------------------------------------------------------------------------------
    if (Test-Path $junitFile) {
        [xml]$junit = Get-Content -Path $junitFile -Raw
        $cases = @($junit.SelectNodes('//testcase'))
        $failed = @($cases | Where-Object { $_.SelectSingleNode('failure') -or $_.SelectSingleNode('error') })
        $skipped = @($cases | Where-Object { $_.SelectSingleNode('skipped') })
        Write-Host ''
        Write-Host ('SUMMARY: {0} tests, {1} failed, {2} skipped' -f $cases.Count, $failed.Count, $skipped.Count)
        foreach ($case in $failed) {
            $node = if ($case.SelectSingleNode('failure')) { $case.SelectSingleNode('failure') } else { $case.SelectSingleNode('error') }
            Write-Host ('  FAILED {0} / {1}: {2}' -f $case.classname, $case.name, $node.message)
        }
    }
}
finally {
    $phaseTimer.Restart()
    if ((-not $KeepApps) -and ($null -ne $keepIds)) {
        # One session: everything this run installed (not Microsoft) is uninstalled without data and schema; the apps of
        # the repo are unpublished, the dependencies stay published for the next run
        Invoke-ScriptInBcContainer -containerName $ContainerName -argumentList $containerSide, $repoIds, $keepIds -scriptblock {
            Param([string] $containerSide, [string[]] $repoIds, [string[]] $keepIds)
            . $containerSide
            $installedByRun = @(Get-NAVAppInfo -ServerInstance $ServerInstance -Tenant default -TenantSpecificProperties |
                Where-Object { $_.IsInstalled -and ($_.Publisher -ne 'Microsoft') -and ($keepIds -notcontains "$($_.AppId)") })
            Remove-TestApps -Apps $installedByRun
            $repoApps = @(Get-NAVAppInfo -ServerInstance $ServerInstance -Tenant default -TenantSpecificProperties | Where-Object { $repoIds -contains "$($_.AppId)" })
            Remove-TestApps -Apps $repoApps -Unpublish
        }
    }
    # The sources and symbols of the run are not needed any more (the Base Application symbols alone take tens of MB)
    Remove-Item -Path $srcFolder, $symbolsFolder -Recurse -Force -ErrorAction SilentlyContinue
    $phaseSeconds['cleanup'] += $phaseTimer.Elapsed.TotalSeconds
    Write-Host ('TIMING: {0}, total {1:mm\:ss}' -f (($phaseSeconds.GetEnumerator() | ForEach-Object { '{0} {1:N0} s' -f $_.Key, $_.Value }) -join ', '), $totalTimer.Elapsed)
    Write-Host "Run folder: $runFolder"
    Stop-Transcript | Out-Null
}
if (-not $allPassed) { exit 1 }

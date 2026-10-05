# Publishes the apps of an AL repo into the shared test container, runs the tests of its test apps and removes the
# apps again - the way the Essence pipeline does it: dependencies from BCNugetPackages (latest in the MajorMinor range of
# the declared minimum), apps compiled and installed in dependency order, test apps = apps with "Test" in the name.
# Starts Docker Desktop and the container when they are stopped. A repo without a test app ends right away.
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
        Id           = "$($json.id)"
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

function Get-DependencyId($dependency) {
    if ($dependency.PSObject.Properties.Name -contains 'id') { return "$($dependency.id)" }
    return "$($dependency.appId)"
}

function Remove-ContainerApp($appInfo) {
    Write-Host "Removing $($appInfo.Name) $($appInfo.Version)"
    UnPublish-BcContainerApp -containerName $ContainerName -name $appInfo.Name -publisher $appInfo.Publisher -version $appInfo.Version `
        -unInstall -doNotSaveData -doNotSaveSchema -force
}

function Install-MicrosoftApp([string] $appId, [string] $appName) {
    # A Microsoft app the container does not have installed (e.g. AI Test Toolkit) - taken from the artifact in the container
    Invoke-ScriptInBcContainer -containerName $ContainerName -argumentList $appId, $appName -scriptblock {
        Param($appId, $appName)
        $candidates = @(Get-ChildItem -Path 'C:\Applications' -Filter '*.app' -Recurse | Where-Object { $_.Name -like "*$appName*" })
        $file = $candidates | Where-Object { "$((Get-NAVAppInfo -Path $_.FullName).AppId)" -eq $appId } | Select-Object -First 1
        if (-not $file) { throw "Microsoft app $appName ($appId) is not in C:\Applications of the container." }
        $info = Get-NAVAppInfo -Path $file.FullName
        Write-Host "Installing $($info.Name) $($info.Version) from $($file.FullName)"
        Publish-NAVApp -ServerInstance $ServerInstance -Path $file.FullName -SkipVerification
        Sync-NAVApp -ServerInstance $ServerInstance -Name $info.Name -Publisher $info.Publisher -Version $info.Version
        Install-NAVApp -ServerInstance $ServerInstance -Name $info.Name -Publisher $info.Publisher -Version $info.Version
    }
}

$allPassed = $false
# Apps published before this run started (after removing leftovers of this repo) - the cleanup removes only the others
$baseline = $null
try {
    Start-TestContainer -ContainerName $ContainerName
    $credential = Get-TestContainerCredential
    if (-not (Test-Path $TestContainerSettings.patFile)) { throw "PAT file $($TestContainerSettings.patFile) not found (settings.json, patFile)." }
    $nuGetToken = (Get-Content -Path $TestContainerSettings.patFile -Raw).Trim()

    # --- Clean slate: apps of this repo left by an earlier run, and a warning about apps of other repos ---------------
    $published = @(Get-BcContainerAppInfo -containerName $ContainerName -tenantSpecificProperties -sort DependenciesLast)
    $published | Where-Object { $repoIds -contains "$($_.AppId)" } | ForEach-Object { Remove-ContainerApp $_ }
    $foreign = @($published | Where-Object { $_.Publisher -ne 'Microsoft' -and $repoIds -notcontains "$($_.AppId)" })
    if ($foreign) {
        Write-Warning ('The container has apps of another run: {0} - remove them if they collide (object IDs).' -f (($foreign | ForEach-Object { "$($_.Name) $($_.Version)" }) -join ', '))
    }
    $baseline = @(Get-BcContainerAppInfo -containerName $ContainerName | ForEach-Object { "$($_.AppId):$($_.Version)" })

    # --- External dependencies -------------------------------------------------------------------------------------
    $external = @{}
    $microsoft = @{}
    foreach ($app in $apps) {
        foreach ($dependency in $app.Dependencies) {
            $dependencyId = Get-DependencyId $dependency
            if ($repoIds -contains $dependencyId) { continue }
            $target = if ($dependency.publisher -eq 'Microsoft') { $microsoft } else { $external }
            if (-not $target.ContainsKey($dependencyId) -or ([version]$dependency.version -gt [version]$target[$dependencyId].version)) {
                $target[$dependencyId] = $dependency
            }
        }
    }
    $installedIds = @(Get-BcContainerAppInfo -containerName $ContainerName -tenantSpecificProperties | Where-Object { $_.IsInstalled } | ForEach-Object { "$($_.AppId)" })
    foreach ($entry in $microsoft.GetEnumerator()) {
        if ($installedIds -notcontains $entry.Key) { Install-MicrosoftApp -appId $entry.Key -appName $entry.Value.name }
    }
    foreach ($entry in $external.GetEnumerator()) {
        $minimum = [version]$entry.Value.version
        # The pipeline: MajorMinor range of the declared minimum, latest version in it
        $range = '[{0},{1}.{2}.0.0)' -f $minimum, $minimum.Major, ($minimum.Minor + 1)
        $packageId = Get-BcNuGetPackageId -publisher $entry.Value.publisher -name $entry.Value.name -id $entry.Key
        Write-Host "Dependency $($entry.Value.name) $range from NuGet ($packageId)"
        Publish-BcNuGetPackageToContainer -nuGetServerUrl $TestContainerSettings.nuGetServerUrl -nuGetToken $nuGetToken -packageName $packageId `
            -version $range -select Latest -containerName $ContainerName -appSymbolsFolder $symbolsFolder -skipVerification
    }

    # --- Compile and install the apps of the repo ------------------------------------------------------------------
    foreach ($app in $apps) {
        $source = Join-Path $RepoPath $app.Folder
        $target = Join-Path $srcFolder $app.Folder
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        # robocopy: exit codes below 8 are success
        robocopy $source $target /E /NFL /NDL /NJH /NJS /NP /XD .alpackages .output output .snapshots .git /XF *.app | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "Copying $source failed (robocopy $LASTEXITCODE)" }
    }
    foreach ($app in $apps) {
        Write-Host "Compiling $($app.Name)"
        $appFile = Compile-AppInBcContainer -containerName $ContainerName -credential $credential `
            -appProjectFolder (Join-Path $srcFolder $app.Folder) -appOutputFolder $outputFolder -appSymbolsFolder $symbolsFolder `
            -CopyAppToSymbolsFolder -basePath $srcFolder
        Publish-BcContainerApp -containerName $ContainerName -appFile $appFile -skipVerification -sync -syncMode ForceSync -install
    }

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
    if ((-not $KeepApps) -and ($null -ne $baseline)) {
        # Everything this run added that is not Microsoft (the toolkit apps stay for the next run)
        Get-BcContainerAppInfo -containerName $ContainerName -tenantSpecificProperties -sort DependenciesLast |
            Where-Object { $_.Publisher -ne 'Microsoft' -and $baseline -notcontains "$($_.AppId):$($_.Version)" } |
            ForEach-Object { Remove-ContainerApp $_ }
    }
    Write-Host "Run folder: $runFolder"
    Stop-Transcript | Out-Null
}
if (-not $allPassed) { exit 1 }

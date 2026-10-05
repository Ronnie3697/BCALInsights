# Functions that run INSIDE the test container. Test-Repo.ps1 copies this file into the run folder (shared with the
# container) and dot-sources it in Invoke-ScriptInBcContainer - one session per step instead of one per app and
# operation, which is where BcContainerHelper spends most of the time (a session per call, app info read again).
# $ServerInstance is set by the container session.

function Get-TestAppDependencyIds($app) {
    # The app ids the given published app depends on
    $details = Get-NAVAppInfo -ServerInstance $ServerInstance -Id $app.AppId -Version $app.Version
    @($details.Dependencies | ForEach-Object { "$($_.AppId)" })
}

function Get-TestAppsDependentsFirst([object[]] $Apps) {
    # Orders the apps so that an app comes before the apps (of the list) it depends on
    $pending = [System.Collections.ArrayList]@($Apps)
    $dependencyIds = @{}
    foreach ($app in $pending) { $dependencyIds["$($app.AppId):$($app.Version)"] = Get-TestAppDependencyIds $app }
    $ordered = @()
    while ($pending.Count -gt 0) {
        $next = $null
        foreach ($candidate in $pending) {
            $isNeeded = $false
            foreach ($other in $pending) {
                if (($other -ne $candidate) -and ($dependencyIds["$($other.AppId):$($other.Version)"] -contains "$($candidate.AppId)")) { $isNeeded = $true }
            }
            if (-not $isNeeded) { $next = $candidate; break }
        }
        if (-not $next) { throw 'The apps to remove depend on each other in a cycle.' }
        $ordered += $next
        $pending.Remove($next)
    }
    $ordered
}

function Remove-TestApps([object[]] $Apps, [switch] $Unpublish) {
    # Uninstalls the installed ones without keeping data and schema, dependents first; unpublishes all of them when asked
    if (-not $Apps) { return }
    foreach ($app in (Get-TestAppsDependentsFirst $Apps)) {
        if ($app.IsInstalled) {
            Write-Host "Uninstalling $($app.Name) $($app.Version)"
            Uninstall-NAVApp -ServerInstance $ServerInstance -Name $app.Name -Publisher $app.Publisher -Version $app.Version -DoNotSaveData -Force
            Sync-NAVApp -ServerInstance $ServerInstance -Name $app.Name -Publisher $app.Publisher -Version $app.Version -Mode Clean -Force
        }
        if ($Unpublish) {
            Write-Host "Unpublishing $($app.Name) $($app.Version)"
            Unpublish-NAVApp -ServerInstance $ServerInstance -Name $app.Name -Publisher $app.Publisher -Version $app.Version
        }
    }
}

function Install-TestAppFiles([string[]] $Files, [string] $SyncMode = 'Add') {
    # Publishes what is not published yet and syncs and installs what is not installed, in the order given (dependencies
    # first). Older versions of the same app that are not installed are unpublished. Outputs INSTALLED:<app id> lines.
    foreach ($file in $Files) {
        $info = Get-NAVAppInfo -Path $file
        $versions = @(Get-NAVAppInfo -ServerInstance $ServerInstance -Tenant default -TenantSpecificProperties -Id $info.AppId)
        $other = @($versions | Where-Object { ($_.Version -ne $info.Version) -and $_.IsInstalled })
        if ($other) {
            throw "$($info.Name) $($other[0].Version) is installed already (left by a run with -KeepApps?) - $($info.Version) cannot be installed next to it."
        }
        $same = $versions | Where-Object { $_.Version -eq $info.Version } | Select-Object -First 1
        if (-not $same) {
            Write-Host "Publishing $($info.Name) $($info.Version)"
            Publish-NAVApp -ServerInstance $ServerInstance -Path $file -SkipVerification
        }
        if (-not ($same -and $same.IsInstalled)) {
            Write-Host "Installing $($info.Name) $($info.Version)"
            if ($SyncMode -eq 'ForceSync') {
                Sync-NAVApp -ServerInstance $ServerInstance -Name $info.Name -Publisher $info.Publisher -Version $info.Version -Mode ForceSync -Force
            }
            else {
                Sync-NAVApp -ServerInstance $ServerInstance -Name $info.Name -Publisher $info.Publisher -Version $info.Version
            }
            Install-NAVApp -ServerInstance $ServerInstance -Name $info.Name -Publisher $info.Publisher -Version $info.Version
            "INSTALLED:$($info.AppId)"
        }
        foreach ($old in @($versions | Where-Object { ($_.Version -ne $info.Version) -and (-not $_.IsInstalled) })) {
            Write-Host "Unpublishing the older $($old.Name) $($old.Version)"
            Unpublish-NAVApp -ServerInstance $ServerInstance -Name $old.Name -Publisher $old.Publisher -Version $old.Version
        }
    }
}

function Install-MicrosoftAppFromArtifact([string] $AppId, [string] $NameFilter) {
    # A Microsoft app the container does not have installed (e.g. AI Test Toolkit) - taken from the artifact in the container
    $file = Get-ChildItem -Path 'C:\Applications' -Filter '*.app' -Recurse |
        Where-Object { $_.Name -like "*$NameFilter*" } |
        Where-Object { "$((Get-NAVAppInfo -Path $_.FullName).AppId)" -eq $AppId } | Select-Object -First 1
    if (-not $file) { throw "Microsoft app $NameFilter ($AppId) is not in C:\Applications of the container." }
    Install-TestAppFiles -Files @($file.FullName)
}

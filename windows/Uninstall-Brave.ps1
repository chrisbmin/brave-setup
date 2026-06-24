#Requires -Version 5.1
<#
  Uninstall-Brave.ps1

  Completely removes Brave Browser from this machine: the application itself,
  all of its user data (bookmarks, passwords, history, extensions, profiles),
  and every setting applied by Set-BraveConfig.ps1 (registry policy keys,
  Local State / profile Preferences edits).

  This is destructive and irreversible - it deletes your Brave profile data.
  Requires typed "YES" confirmation unless -Force is passed.

  Usage:
    irm <raw-url-to-this-file> | iex
    & ([scriptblock]::Create((irm <raw-url-to-this-file>))) -DryRun
    & ([scriptblock]::Create((irm <raw-url-to-this-file>))) -Force   # skip the typed confirmation
#>

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$ScriptUrl = 'https://raw.githubusercontent.com/chrisbmin/brave-setup/main/windows/Uninstall-Brave.ps1'

$PolicyPath = 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave'
$PolicyNames = @(
    'BraveAIChatEnabled', 'BraveWalletDisabled', 'BraveRewardsDisabled',
    'BraveVPNDisabled', 'BraveNewsDisabled', 'BraveTalkDisabled', 'PromotionalTabsEnabled'
)

$DataPaths = @(
    (Join-Path $env:LOCALAPPDATA 'BraveSoftware'),
    (Join-Path $env:APPDATA 'BraveSoftware'),
    (Join-Path $env:ProgramFiles 'BraveSoftware'),
    "${env:ProgramFiles(x86)}\BraveSoftware",
    (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Brave Browser.lnk'),
    (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Brave Browser.lnk'),
    (Join-Path $env:PUBLIC 'Desktop\Brave Browser.lnk'),
    (Join-Path $env:USERPROFILE 'Desktop\Brave Browser.lnk')
)

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Elevated {
    $switches = @()
    if ($Force) { $switches += '-Force' }
    if ($DryRun) { $switches += '-DryRun' }

    if ($PSCommandPath) {
        $argList = @('-NoProfile', '-File', "`"$PSCommandPath`"") + $switches
    } else {
        $remoteInvoke = "irm '$ScriptUrl' | iex"
        if ($switches.Count -gt 0) {
            $remoteInvoke = "& ([scriptblock]::Create((irm '$ScriptUrl'))) $($switches -join ' ')"
        }
        $argList = @('-NoProfile', '-Command', $remoteInvoke)
    }

    Write-Host "Administrator privileges are required. Relaunching elevated..." -ForegroundColor Yellow
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs | Out-Null
}

function Confirm-Destructive {
    if ($Force -or $DryRun) { return $true }

    Write-Host ""
    Write-Host "WARNING: this will COMPLETELY remove Brave Browser from this computer," -ForegroundColor Red
    Write-Host "including ALL of its data: bookmarks, saved passwords, browsing history," -ForegroundColor Red
    Write-Host "and extensions. This cannot be undone." -ForegroundColor Red
    Write-Host ""
    $reply = Read-Host 'Type YES (all caps) to continue'
    return $reply -ceq 'YES'
}

function Stop-Brave {
    $proc = Get-Process -Name 'brave' -ErrorAction SilentlyContinue
    if ($proc) {
        if ($DryRun) {
            Write-Host "[DryRun] Would close running Brave Browser process."
        } else {
            Write-Host "Closing Brave Browser..."
            Stop-Process -Name 'brave' -Force
            Start-Sleep -Seconds 1
        }
    }
}

function Remove-Policies {
    if (-not (Test-Path $PolicyPath)) { return }
    foreach ($name in $PolicyNames) {
        if ($DryRun) {
            Write-Host "[DryRun] Would remove $PolicyPath\$name"
            continue
        }
        if (Get-ItemProperty -Path $PolicyPath -Name $name -ErrorAction SilentlyContinue) {
            Remove-ItemProperty -Path $PolicyPath -Name $name -Force
            Write-Host "Removed policy $name"
        }
    }
}

function Uninstall-BraveApp {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        if ($DryRun) {
            Write-Host "[DryRun] Would run: winget uninstall --id Brave.Brave -e --silent"
        } else {
            Write-Host "Uninstalling Brave via winget..."
            winget uninstall --id Brave.Brave -e --silent 2>$null
        }
    }

    # Fall back to (or also run) the registry-sourced uninstaller, in case winget
    # isn't present or didn't know about this install (e.g. installed by the direct
    # download method).
    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $entries = Get-ItemProperty -Path $uninstallRoots -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like 'Brave*' -and $_.UninstallString }

    foreach ($entry in $entries) {
        $cmd = "$($entry.UninstallString) --force-uninstall"
        if ($DryRun) {
            Write-Host "[DryRun] Would run: $cmd"
            continue
        }
        Write-Host "Running uninstaller: $cmd"
        Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', $cmd -Wait -ErrorAction SilentlyContinue
    }
}

function Remove-LeftoverData {
    foreach ($path in $DataPaths) {
        if (-not (Test-Path $path)) { continue }
        if ($DryRun) {
            Write-Host "[DryRun] Would delete: $path"
        } else {
            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "Deleted: $path"
        }
    }

    $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like '*Brave*' }
    foreach ($task in $tasks) {
        if ($DryRun) {
            Write-Host "[DryRun] Would remove scheduled task: $($task.TaskName)"
        } else {
            Unregister-ScheduledTask -TaskName $task.TaskName -Confirm:$false -ErrorAction SilentlyContinue
            Write-Host "Removed scheduled task: $($task.TaskName)"
        }
    }
}

# --- main ---

if (-not $DryRun -and -not (Test-Admin)) {
    Invoke-Elevated
    return
}

if (-not (Confirm-Destructive)) {
    Write-Host "Cancelled. Nothing was changed."
    return
}

Stop-Brave
Remove-Policies
Uninstall-BraveApp
Remove-LeftoverData

if (-not $DryRun) {
    Write-Host ""
    Write-Host "Done. Brave Browser and its settings/data have been removed." -ForegroundColor Green
}

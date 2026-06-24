#Requires -Version 5.1
<#
  Set-BraveConfig.ps1

  Configures Brave Browser via the official enterprise policy registry keys
  (HKLM\SOFTWARE\Policies\BraveSoftware\Brave) plus a small edit to the
  per-user Local State file for the one setting with no policy equivalent
  (Widevine). See ../policies-reference.md for the full list and sources.

  Usage:
    irm <raw-url-to-this-file> | iex
    & ([scriptblock]::Create((irm <raw-url-to-this-file>))) -Uninstall
    & ([scriptblock]::Create((irm <raw-url-to-this-file>))) -DryRun
#>

[CmdletBinding()]
param(
    [switch]$Uninstall,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# Used to re-launch elevated when invoked via `irm <url> | iex` (no local file path to relaunch from).
$ScriptUrl = 'https://raw.githubusercontent.com/REPLACE_ME/brave-setup/main/windows/Set-BraveConfig.ps1'

$PolicyPath = 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave'

# name -> disabled/suppressed value (DWORD 0/1)
$Policies = [ordered]@{
    BraveAIChatEnabled       = 0  # Leo AI
    BraveWalletDisabled      = 1  # Web3 Wallet
    BraveRewardsDisabled     = 1
    BraveVPNDisabled         = 1
    BraveNewsDisabled        = 1
    BraveTalkDisabled        = 1
    PromotionalTabsEnabled   = 0  # welcome/promo tabs, incl. the sync nag (Sync itself stays enabled)
}

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Elevated {
    $switches = @()
    if ($Uninstall) { $switches += '-Uninstall' }
    if ($DryRun) { $switches += '-DryRun' }

    if ($PSCommandPath) {
        # Running from a local file (e.g. a downloaded copy) - relaunch that same file.
        $argList = @('-NoProfile', '-File', "`"$PSCommandPath`"") + $switches
    } else {
        # Running via `irm <url> | iex` - no local file to relaunch, so re-fetch the script.
        $remoteInvoke = "irm '$ScriptUrl' | iex"
        if ($switches.Count -gt 0) {
            $remoteInvoke = "& ([scriptblock]::Create((irm '$ScriptUrl'))) $($switches -join ' ')"
        }
        $argList = @('-NoProfile', '-Command', $remoteInvoke)
    }

    Write-Host "Administrator privileges are required. Relaunching elevated..." -ForegroundColor Yellow
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs | Out-Null
}

function Set-Policies {
    if (-not (Test-Path $PolicyPath)) {
        if ($DryRun) {
            Write-Host "[DryRun] Would create registry key: $PolicyPath"
        } else {
            New-Item -Path $PolicyPath -Force | Out-Null
        }
    }

    foreach ($name in $Policies.Keys) {
        $value = $Policies[$name]
        if ($DryRun) {
            Write-Host "[DryRun] Would set $PolicyPath\$name = $value (DWORD)"
        } else {
            New-ItemProperty -Path $PolicyPath -Name $name -Value $value -PropertyType DWord -Force | Out-Null
            Write-Host "Set $name = $value"
        }
    }
}

function Remove-Policies {
    if (-not (Test-Path $PolicyPath)) {
        Write-Host "No policy key present at $PolicyPath; nothing to remove."
        return
    }

    foreach ($name in $Policies.Keys) {
        if ($DryRun) {
            Write-Host "[DryRun] Would remove $PolicyPath\$name"
            continue
        }
        if (Get-ItemProperty -Path $PolicyPath -Name $name -ErrorAction SilentlyContinue) {
            Remove-ItemProperty -Path $PolicyPath -Name $name -Force
            Write-Host "Removed $name"
        }
    }
}

function Stop-Brave {
    $proc = Get-Process -Name 'brave' -ErrorAction SilentlyContinue
    if ($proc) {
        if ($DryRun) {
            Write-Host "[DryRun] Would close running Brave Browser process."
        } else {
            Write-Host "Closing Brave Browser to safely edit its Local State file..."
            Stop-Process -Name 'brave' -Force
            Start-Sleep -Seconds 1
        }
    }
}

function Get-LocalStatePath {
    return Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data\Local State'
}

function Set-WidevinePrefs {
    param([bool]$Enabled)

    $path = Get-LocalStatePath
    if (-not (Test-Path $path)) {
        Write-Host "Local State not found at $path (Brave may not be installed for this user) - skipping Widevine prefs."
        return
    }

    if ($DryRun) {
        Write-Host "[DryRun] Would set brave.widevine_opted_in = $Enabled and brave.ask_widevine_install = $false in:`n  $path"
        return
    }

    $backup = "$path.bak"
    if (-not (Test-Path $backup)) {
        Copy-Item -Path $path -Destination $backup
    }

    $json = Get-Content -Path $path -Raw | ConvertFrom-Json

    if (-not $json.PSObject.Properties['brave']) {
        $json | Add-Member -MemberType NoteProperty -Name 'brave' -Value ([PSCustomObject]@{})
    }

    foreach ($prop in @{ widevine_opted_in = $Enabled; ask_widevine_install = $false }.GetEnumerator()) {
        if ($json.brave.PSObject.Properties[$prop.Key]) {
            $json.brave.$($prop.Key) = $prop.Value
        } else {
            $json.brave | Add-Member -MemberType NoteProperty -Name $prop.Key -Value $prop.Value
        }
    }

    $jsonText = $json | ConvertTo-Json -Depth 100 -Compress
    # Write without a BOM - Chromium's JSON parser rejects a leading BOM.
    [System.IO.File]::WriteAllText($path, $jsonText, [System.Text.UTF8Encoding]::new($false))

    Write-Host "Set brave.widevine_opted_in = $Enabled in Local State"
}

# --- main ---

if (-not $DryRun -and -not (Test-Admin)) {
    Invoke-Elevated
    return
}

if ($Uninstall) {
    Write-Host "Reverting Brave policy settings..." -ForegroundColor Cyan
    Stop-Brave
    Remove-Policies
    Set-WidevinePrefs -Enabled $false
} else {
    Write-Host "Applying Brave policy settings..." -ForegroundColor Cyan
    Stop-Brave
    Set-Policies
    Set-WidevinePrefs -Enabled $true
}

if (-not $DryRun) {
    Write-Host ""
    Write-Host "Done. Start Brave and check:" -ForegroundColor Green
    Write-Host "  brave://policy              (confirm the policies above are listed as 'Applied')"
    Write-Host "  brave://settings/extensions (confirm Widevine is enabled)"
}

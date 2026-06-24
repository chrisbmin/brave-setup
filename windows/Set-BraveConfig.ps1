#Requires -Version 5.1
<#
  Set-BraveConfig.ps1

  Configures Brave Browser via:
  - the official enterprise policy registry keys
    (HKLM\SOFTWARE\Policies\BraveSoftware\Brave) for things that should be
    fully removed (Leo AI, Wallet, Rewards, VPN, News, Talk, promo tabs)
  - direct edits to Brave's JSON pref files for plain preferences that have
    no policy equivalent and shouldn't be enterprise-locked (Widevine in
    Local State; home button / wide address bar / full URLs / rounded
    corners / search suggestions / web discovery in the profile
    Preferences file)

  See ../policies-reference.md for the full list and sources.

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
$ScriptUrl = 'https://raw.githubusercontent.com/chrisbmin/brave-setup/main/windows/Set-BraveConfig.ps1'

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

# dotted JSON path in Local State -> On/Off values (Off = upstream default, for clean -Uninstall)
$LocalStatePrefs = [ordered]@{
    'brave.widevine_opted_in'     = @{ On = $true;  Off = $false }
    'brave.ask_widevine_install'  = @{ On = $false; Off = $true  }
}

# dotted JSON path in the profile Preferences file -> On/Off values (Off = upstream default)
$ProfilePrefs = [ordered]@{
    'browser.show_home_button'      = @{ On = $true; Off = $false }  # Show home button
    'brave.location_bar_is_wide'    = @{ On = $true; Off = $false }  # Use wide address bar
    'omnibox.prevent_url_elisions'  = @{ On = $true; Off = $false }  # Always show full URLs
    'brave.web_view_rounded_corners'= @{ On = $true; Off = $true  }  # Rounded corners (already the upstream default)
    'search.suggest_enabled'        = @{ On = $true; Off = $true  }  # Improve search suggestions (already the upstream default)
    'brave.web_discovery_enabled'   = @{ On = $true; Off = $false }  # Web Discovery Project
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
            Write-Host "Closing Brave Browser to safely edit its JSON pref files..."
            Stop-Process -Name 'brave' -Force
            Start-Sleep -Seconds 1
        }
    }
}

function Get-LocalStatePath {
    return Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data\Local State'
}

function Get-ProfilePreferencesPath {
    # Targets the "Default" profile. If you use a different/additional profile,
    # apply the same edits under "User Data\<Profile Name>\Preferences".
    return Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data\Default\Preferences'
}

function Set-JsonPath {
    param($Root, [string]$DottedPath, $Value)

    $parts = $DottedPath -split '\.'
    $node = $Root
    for ($i = 0; $i -lt $parts.Count - 1; $i++) {
        $key = $parts[$i]
        if (-not $node.PSObject.Properties[$key] -or $node.$key -isnot [PSCustomObject]) {
            if ($node.PSObject.Properties[$key]) {
                $node.$key = [PSCustomObject]@{}
            } else {
                $node | Add-Member -MemberType NoteProperty -Name $key -Value ([PSCustomObject]@{})
            }
        }
        $node = $node.$key
    }

    $lastKey = $parts[-1]
    if ($node.PSObject.Properties[$lastKey]) {
        $node.$lastKey = $Value
    } else {
        $node | Add-Member -MemberType NoteProperty -Name $lastKey -Value $Value
    }
}

function Set-JsonFilePrefs {
    param(
        [string]$Path,
        [System.Collections.Specialized.OrderedDictionary]$Prefs,
        [bool]$Enable
    )

    if (-not (Test-Path $Path)) {
        Write-Host "Not found: $Path (Brave may not be installed/run for this profile) - skipping."
        return
    }

    if ($DryRun) {
        foreach ($key in $Prefs.Keys) {
            $value = if ($Enable) { $Prefs[$key].On } else { $Prefs[$key].Off }
            Write-Host "[DryRun] Would set $key = $value in:`n  $Path"
        }
        return
    }

    $backup = "$Path.bak"
    if (-not (Test-Path $backup)) {
        Copy-Item -Path $Path -Destination $backup
    }

    $json = Get-Content -Path $Path -Raw | ConvertFrom-Json

    foreach ($key in $Prefs.Keys) {
        $value = if ($Enable) { $Prefs[$key].On } else { $Prefs[$key].Off }
        Set-JsonPath -Root $json -DottedPath $key -Value $value
        Write-Host "Set $key = $value"
    }

    $jsonText = $json | ConvertTo-Json -Depth 100 -Compress
    # Write without a BOM - Chromium's JSON parser rejects a leading BOM.
    [System.IO.File]::WriteAllText($Path, $jsonText, [System.Text.UTF8Encoding]::new($false))
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
    Set-JsonFilePrefs -Path (Get-LocalStatePath) -Prefs $LocalStatePrefs -Enable $false
    Set-JsonFilePrefs -Path (Get-ProfilePreferencesPath) -Prefs $ProfilePrefs -Enable $false
} else {
    Write-Host "Applying Brave policy settings..." -ForegroundColor Cyan
    Stop-Brave
    Set-Policies
    Set-JsonFilePrefs -Path (Get-LocalStatePath) -Prefs $LocalStatePrefs -Enable $true
    Set-JsonFilePrefs -Path (Get-ProfilePreferencesPath) -Prefs $ProfilePrefs -Enable $true
}

if (-not $DryRun) {
    Write-Host ""
    Write-Host "Done. Start Brave and check:" -ForegroundColor Green
    Write-Host "  brave://policy              (confirm the policies above are listed as 'Applied')"
    Write-Host "  brave://settings/extensions (confirm Widevine is enabled)"
    Write-Host "  brave://settings/appearance (confirm home button / wide address bar / full URLs / rounded corners)"
    Write-Host "  brave://settings/search     (confirm search suggestions / web discovery)"
    Write-Host ""
    Write-Host "Not scripted (no safe pref/policy path - set these by hand once):" -ForegroundColor Yellow
    Write-Host "  brave://settings/shields -> Block fingerprinting -> On"
    Write-Host "  brave://settings/search  -> Default search engine (Normal and Private window) -> Brave"
}

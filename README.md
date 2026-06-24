# brave-setup

One-liner scripts that configure Brave Browser the way I like it: Leo AI off, the
Web3 Wallet off, Rewards/VPN/News/Talk off, promo nags suppressed (Sync stays on),
Widevine DRM playback on, and a set of appearance/search preferences (wide address
bar, full URLs, rounded corners, search suggestions, Web Discovery) turned on.

Settings that should be fully removed/locked use Brave/Chromium's official
enterprise policy mechanism (registry on Windows, managed-preferences plist on
macOS) - This is the same mechanism IT departments use, and it survives Brave updates.
Plain preferences that you should still be able to change later via the Settings
UI (Widevine, and the appearance/search toggles) are written directly into Brave's
own JSON pref files instead, so nothing gets enterprise-locked unnecessarily. See
[`policies-reference.md`](policies-reference.md) for the full list of keys, values,
and sources.

If Brave isn't installed yet, the setup script checks for it first and stops: it
prints a reminder to grab it from [brave.com/download](https://brave.com/download/),
launch it once, and re-run the script — none of the settings apply until Brave has
actually been installed and run, so there's no point continuing further. (The
revert/uninstall paths skip this check, since they don't need Brave to be present.)

### Manual Steps
Three settings need to be configured manually in Settings: 
1. Appearance → Show home button 
2. Shields → Block fingerprinting
3. Search engine → the default search engine for Normal/Private windows set to Brave
Unfortunately, there is no safe, stable key to script on for these settings, so we'll set them manually — see the bottom of
[`policies-reference.md`](policies-reference.md) for why and the couple of clicks
needed to set them by hand.

**Before piping any of this into your shell**: read the script first. That's good
practice for any `irm | iex` / `curl | bash` installer, not just this one - all
four scripts are short and plain text, linked below.

- [`windows/Set-BraveConfig.ps1`](windows/Set-BraveConfig.ps1)
- [`windows/Uninstall-Brave.ps1`](windows/Uninstall-Brave.ps1)
- [`macos/set-brave-config.sh`](macos/set-brave-config.sh)
- [`macos/uninstall-brave.sh`](macos/uninstall-brave.sh)

## Install

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/chrisbmin/brave-setup/main/windows/Set-BraveConfig.ps1 | iex
```

The script will relaunch itself elevated (UAC prompt) since writing the policy
requires admin rights. If Brave isn't found, it prints a link to
[brave.com/download](https://brave.com/download/) and stops — install Brave,
launch it once, then re-run.

### macOS

```bash
curl -fsSL https://raw.githubusercontent.com/chrisbmin/brave-setup/main/macos/set-brave-config.sh | sudo bash
```

`sudo` is required up front to write the managed-preferences plist. If Brave isn't
found, it prints a link to [brave.com/download](https://brave.com/download/) and
stops — install Brave, launch it once, then re-run.

Once the repo is public, wrap either raw URL above in a shortlink (e.g. a
custom domain or bit.ly/tinyurl) for easier typing/sharing.

## Dry run

See what would change without writing anything:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/chrisbmin/brave-setup/main/windows/Set-BraveConfig.ps1))) -DryRun
```

```bash
curl -fsSL https://raw.githubusercontent.com/chrisbmin/brave-setup/main/macos/set-brave-config.sh | sudo bash -s -- --dry-run
```

## Revert settings only (keeps Brave installed)

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/chrisbmin/brave-setup/main/windows/Set-BraveConfig.ps1))) -Uninstall
```

```bash
curl -fsSL https://raw.githubusercontent.com/chrisbmin/brave-setup/main/macos/set-brave-config.sh | sudo bash -s -- --uninstall
```

This removes the policy keys/values this repo adds and reverts the JSON pref edits
back to their upstream defaults. Brave itself, and your profile data, are left
alone.

After running either script, fully quit and restart Brave, then check
`brave://policy` (policies applied) and `brave://settings/extensions` (Widevine
toggle) to confirm.

## Full uninstall (removes Brave and all its data)

```powershell
irm https://raw.githubusercontent.com/chrisbmin/brave-setup/main/windows/Uninstall-Brave.ps1 | iex
```

```bash
curl -fsSL https://raw.githubusercontent.com/chrisbmin/brave-setup/main/macos/uninstall-brave.sh | sudo bash
```

**This is destructive and irreversible.** It removes the Brave application itself
plus all of its data — bookmarks, saved passwords, browsing history, extensions —
in addition to reverting every setting from above. Both scripts require typing
`YES` to confirm before doing anything (pass `-Force` / `--force` to skip the
prompt for scripted/unattended use). Use `-DryRun` / `--dry-run` first if you just
want to see what would be removed.

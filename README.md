# brave-setup

One-liner scripts that configure Brave Browser the way I like it: Leo AI off, the
Web3 Wallet off, Rewards/VPN/News/Talk off, promo nags suppressed (Sync stays on),
Widevine DRM playback on, and a set of appearance/search preferences (home button,
wide address bar, full URLs, rounded corners, search suggestions, Web Discovery)
turned on.

Settings that should be fully removed/locked use Brave/Chromium's official
enterprise policy mechanism (registry on Windows, managed-preferences plist on
macOS) — the same mechanism IT departments use, and it survives Brave updates.
Plain preferences that you should still be able to change later via the Settings
UI (Widevine, and the appearance/search toggles) are written directly into Brave's
own JSON pref files instead, so nothing gets enterprise-locked unnecessarily. See
[`policies-reference.md`](policies-reference.md) for the full list of keys, values,
and sources.

Two settings from the original wishlist (Shields → Block fingerprinting, and the
default search engine for Normal/Private windows) have no safe, stable key to
script — see the bottom of [`policies-reference.md`](policies-reference.md) for why
and the couple of clicks needed to set them by hand.

**Before piping any of this into your shell**: read the script first. That's good
practice for any `irm | iex` / `curl | bash` installer, not just this one — both
scripts are short and plain text, linked below.

- [`windows/Set-BraveConfig.ps1`](windows/Set-BraveConfig.ps1)
- [`macos/set-brave-config.sh`](macos/set-brave-config.sh)

## Install

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/chrisbmin/brave-setup/main/windows/Set-BraveConfig.ps1 | iex
```

The script will relaunch itself elevated (UAC prompt) since writing the policy
requires admin rights.

### macOS

```bash
curl -fsSL https://raw.githubusercontent.com/chrisbmin/brave-setup/main/macos/set-brave-config.sh | sudo bash
```

`sudo` is required up front to write the managed-preferences plist.

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

## Uninstall / revert

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/chrisbmin/brave-setup/main/windows/Set-BraveConfig.ps1))) -Uninstall
```

```bash
curl -fsSL https://raw.githubusercontent.com/chrisbmin/brave-setup/main/macos/set-brave-config.sh | sudo bash -s -- --uninstall
```

This removes the policy keys/values this repo adds and reverts the Widevine
preference. It does not touch anything else.

After running either script, fully quit and restart Brave, then check
`brave://policy` (policies applied) and `brave://settings/extensions` (Widevine
toggle) to confirm.

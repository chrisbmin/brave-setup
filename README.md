# brave-setup

One-liner scripts that configure Brave Browser the way I like it: Leo AI off, the
Web3 Wallet off, Rewards/VPN/News/Talk off, promo nags suppressed (Sync stays on),
and Widevine DRM playback turned on.

Settings are applied via Brave/Chromium's official enterprise policy mechanism
(registry on Windows, managed-preferences plist on macOS) wherever possible, since
that's the same mechanism IT departments use and it survives Brave updates. The one
exception is Widevine, which has no policy and is set directly in Brave's
`Local State` file. See [`policies-reference.md`](policies-reference.md) for the
full list of keys, values, and sources.

**Before piping any of this into your shell**: read the script first. That's good
practice for any `irm | iex` / `curl | bash` installer, not just this one — both
scripts are short and plain text, linked below.

- [`windows/Set-BraveConfig.ps1`](windows/Set-BraveConfig.ps1)
- [`macos/set-brave-config.sh`](macos/set-brave-config.sh)

## Install

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/REPLACE_ME/brave-setup/main/windows/Set-BraveConfig.ps1 | iex
```

The script will relaunch itself elevated (UAC prompt) since writing the policy
requires admin rights.

### macOS

```bash
curl -fsSL https://raw.githubusercontent.com/REPLACE_ME/brave-setup/main/macos/set-brave-config.sh | sudo bash
```

`sudo` is required up front to write the managed-preferences plist.

Once the repo is public, wrap either raw URL above in a shortlink (e.g. a
custom domain or bit.ly/tinyurl) for easier typing/sharing.

## Dry run

See what would change without writing anything:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/REPLACE_ME/brave-setup/main/windows/Set-BraveConfig.ps1))) -DryRun
```

```bash
curl -fsSL https://raw.githubusercontent.com/REPLACE_ME/brave-setup/main/macos/set-brave-config.sh | sudo bash -s -- --dry-run
```

## Uninstall / revert

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/REPLACE_ME/brave-setup/main/windows/Set-BraveConfig.ps1))) -Uninstall
```

```bash
curl -fsSL https://raw.githubusercontent.com/REPLACE_ME/brave-setup/main/macos/set-brave-config.sh | sudo bash -s -- --uninstall
```

This removes the policy keys/values this repo adds and reverts the Widevine
preference. It does not touch anything else.

After running either script, fully quit and restart Brave, then check
`brave://policy` (policies applied) and `brave://settings/extensions` (Widevine
toggle) to confirm.

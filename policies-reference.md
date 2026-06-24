# Policy / preference reference

Everything this repo's scripts change, why, and where the key name comes from.

## Enterprise policies

Applied on Windows under the registry key `HKLM\SOFTWARE\Policies\BraveSoftware\Brave`
(`REG_DWORD`, `0`/`1`), and on macOS in the managed-preferences plist
`/Library/Managed Preferences/com.brave.Browser.plist` (boolean). Brave is built on
Chromium and reads policies the same way Chrome does; `brave://policy` will show
every key below as "Applied" once set correctly.

| Policy | Value set | Effect |
|---|---|---|
| `BraveAIChatEnabled` | `false` | Disables Leo, Brave's built-in AI chat assistant. |
| `BraveWalletDisabled` | `true` | Disables the built-in Web3 Wallet. |
| `BraveRewardsDisabled` | `true` | Disables Brave Rewards and Brave Ads. |
| `BraveVPNDisabled` | `true` | Removes the Brave VPN button and subscription upsells. |
| `BraveNewsDisabled` | `true` | Removes the Brave News feed from the New Tab Page. |
| `BraveTalkDisabled` | `true` | Disables Brave Talk. |
| `PromotionalTabsEnabled` | `false` | A standard Chromium policy that suppresses promotional/welcome tabs (including the "set up Sync" nag) without touching Sync itself. |

Notably **not** set: `SyncDisabled`. That policy removes Brave Sync entirely, not just
the promotional nag for it — left alone here so Sync keeps working.

Sources: [Brave Help Center – Group Policy](https://support.brave.app/hc/en-us/articles/360039248271-Group-Policy),
Brave/Chromium policy lists referenced by community debloating guides
([gist](https://gist.github.com/vil/c52250134d7a6001d625855e1245bdc8),
[corpit.org](https://www.corpit.org/debloating-brave-browser-on-macos-using-policies/)),
cross-checked against `brave://policy` output.

## Local State preferences (no policy equivalent)

Widevine (the DRM component needed for Netflix/Disney+/etc. playback) has no
enterprise policy in Brave — it's a plain preference, stored in the **Local State**
file (not the per-profile `Preferences` file):

- Windows: `%LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data\Local State`
- macOS: `~/Library/Application Support/BraveSoftware/Brave-Browser/Local State`

| Key | Value set | Effect |
|---|---|---|
| `brave.widevine_opted_in` | `true` | Opts in to and enables Widevine. |
| `brave.ask_widevine_install` | `false` | Stops Brave from prompting to install Widevine again. |

Key names confirmed directly from Brave's source:
`inline constexpr char kWidevineEnabled[] = "brave.widevine_opted_in";` and
`inline constexpr char kAskEnableWidvine[] = "brave.ask_widevine_install";`
in [`brave-core/components/constants/pref_names.h`](https://github.com/brave/brave-core/blob/master/components/constants/pref_names.h).

Both scripts back up `Local State` to `Local State.bak` before editing it, and close
Brave first so it can't overwrite the edit on exit.

## Profile preferences (no policy equivalent, and shouldn't be locked)

These are plain appearance/search preferences — defaults you'd set once, not things
that should be enterprise-locked/grayed-out — so they're written directly into the
**profile** `Preferences` file (the "Default" profile) rather than via policy:

- Windows: `%LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data\Default\Preferences`
- macOS: `~/Library/Application Support/BraveSoftware/Brave-Browser/Default/Preferences`

| Key | Value set | Settings UI toggle | Upstream default (used on `--uninstall`) |
|---|---|---|---|
| `browser.show_home_button` | `true` | Appearance → Show home button | `false` |
| `brave.location_bar_is_wide` | `true` | Appearance → Use wide address bar | `false` |
| `omnibox.prevent_url_elisions` | `true` | Appearance → Always show full URLs | `false` |
| `brave.web_view_rounded_corners` | `true` | Appearance → Show rounded corners on main content areas | `true` (already Brave's default) |
| `search.suggest_enabled` | `true` | Search → Improve search suggestions | `true` (already Chromium's default) |
| `brave.web_discovery_enabled` | `true` | Search → Web Discovery Project | `false` |

Key names confirmed directly from Brave's settings-page source (`pref="{{prefs.X}}"`
bindings), not guessed:
[`browser/resources/settings/brave_appearance_page/toolbar.html`](https://github.com/brave/brave-core/blob/master/browser/resources/settings/brave_appearance_page/toolbar.html)
and
[`browser/resources/settings/brave_search_engines_page/brave_search_engines_page.html`](https://github.com/brave/brave-core/blob/master/browser/resources/settings/brave_search_engines_page/brave_search_engines_page.html).

Both scripts back up `Preferences` to `Preferences.bak` before editing it, and close
Brave first.

## Installing Brave (when it's missing)

`Set-BraveConfig.ps1` / `set-brave-config.sh` check whether Brave is already
installed before touching anything install-related. If it's missing, they prompt
before doing anything — install now or skip — and if you say yes, prompt again for
the method:

- **Windows**: `winget install --id Brave.Brave -e --silent` (the official winget
  package; confirmed via its
  [manifest](https://github.com/microsoft/winget-pkgs/blob/master/manifests/b/Brave/Brave/137.1.79.119/Brave.Brave.installer.yaml)),
  or a direct download of Brave's official standalone installer from
  `https://github.com/brave/brave-browser/releases/latest/download/BraveBrowserStandaloneSetup.exe`
  run with `/silent /install` (same switches the winget manifest uses internally).
- **macOS**: `brew install --cask brave-browser` (installing Homebrew itself first,
  with a separate confirmation, if it's not present), or a direct download of
  `https://github.com/brave/brave-browser/releases/latest/download/Brave-Browser-universal.dmg`,
  mounted and copied to `/Applications` directly.

Both download URLs use GitHub's `releases/latest/download/<asset>` redirect, which
always resolves to the current stable release — confirmed against Brave's actual
[latest release](https://github.com/brave/brave-browser/releases/latest), not
guessed or version-pinned.

Declining the install prompt doesn't abort the script — policy settings are still
applied (harmless either way), and the JSON pref edits just no-op until Brave has
been installed and run at least once.

### Not scripted — set these by hand

Two settings from the original request have no safe, stable key to write:

- **Shields → Block fingerprinting**: the toggle calls a live backend API
  (`setFingerprintingControlType` / `setFingerprintingBlockEnabled`) rather than
  reading/writing a simple stored pref, so there's no JSON key to set reliably.
- **Default search engine (Normal and Private window) → Brave**: resolved by
  *list index* at runtime against a dynamically-built engine list
  (`setDefaultPrivateSearchEngine(modelIndex)`), not a stable pref or GUID. The
  Chromium policy route (`DefaultSearchProviderName`/`...SearchURL`) is also
  [confirmed unreliable for selecting Brave's built-in entry](https://community.brave.app/t/make-it-easy-to-make-brave-search-the-default-search-provider-with-chromium-policy/505274)
  by Brave's own community.

Both are a couple of clicks in `brave://settings/shields` and `brave://settings/search`.

## Full uninstall (`Uninstall-Brave.ps1` / `uninstall-brave.sh`)

These are separate, standalone scripts (not a flag on the setup script) that remove
Brave entirely, not just the settings above. Both require typing `YES` to confirm
before doing anything destructive.

App removal:
- **Windows**: tries `winget uninstall --id Brave.Brave -e --silent` first, then
  also looks up Brave's own uninstaller via the registry
  (`HKLM/HKCU ...\Uninstall\*` where `DisplayName -like 'Brave*'`) and runs its
  `UninstallString` with `--force-uninstall` appended — covers installs winget
  doesn't know about (e.g. the direct-download method).
- **macOS**: `brew uninstall --cask brave-browser --zap` if installed via Homebrew,
  otherwise deletes `/Applications/Brave Browser.app` directly.

Leftover data removed on both platforms (in addition to the policy/pref keys from
above): the whole `BraveSoftware` data directory (`%LOCALAPPDATA%`/`%APPDATA%` on
Windows, `~/Library/Application Support` and `~/Library/Caches` on macOS), saved
state, the per-user preferences plist on macOS, Start Menu/Desktop shortcuts and
scheduled tasks on Windows. Compiled from community uninstall guides plus the
script's own dry-run output checked against this repo's actual dev machine.

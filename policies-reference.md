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

#!/usr/bin/env bash
#
# set-brave-config.sh
#
# Configures Brave Browser via:
# - the official enterprise managed-preferences plist
#   (/Library/Managed Preferences/com.brave.Browser.plist) for things that
#   should be fully removed (Leo AI, Wallet, Rewards, VPN, News, Talk, promo
#   tabs)
# - direct edits to Brave's JSON pref files for plain preferences that have
#   no policy equivalent and shouldn't be enterprise-locked (Widevine in
#   Local State; home button / wide address bar / full URLs / rounded
#   corners / search suggestions / web discovery in the profile Preferences
#   file)
#
# See ../policies-reference.md for the full list and sources.
#
# Usage:
#   curl -fsSL <raw-url-to-this-file> | sudo bash
#   curl -fsSL <raw-url-to-this-file> | sudo bash -s -- --uninstall
#   curl -fsSL <raw-url-to-this-file> | sudo bash -s -- --dry-run

set -euo pipefail

UNINSTALL=0
DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --uninstall) UNINSTALL=1 ;;
        --dry-run) DRY_RUN=1 ;;
        *) echo "Unknown argument: $arg" >&2; exit 1 ;;
    esac
done

if [[ "$DRY_RUN" -eq 0 && "$EUID" -ne 0 ]]; then
    echo "This script needs administrator privileges to write Brave's managed preferences." >&2
    echo "Re-run as: curl -fsSL <url> | sudo bash" >&2
    exit 1
fi

PLIST_DOMAIN="com.brave.Browser"
PLIST_PATH="/Library/Managed Preferences/${PLIST_DOMAIN}.plist"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

# Parallel arrays (not associative arrays - macOS ships bash 3.2, which lacks `declare -A`).
POLICY_NAMES=(BraveAIChatEnabled BraveWalletDisabled BraveRewardsDisabled BraveVPNDisabled BraveNewsDisabled BraveTalkDisabled PromotionalTabsEnabled)
POLICY_VALUES=(false true true true true true false)

# dotted JSON path in Local State -> On/Off values (Off = upstream default, for clean --uninstall)
LOCAL_STATE_KEYS=(brave.widevine_opted_in brave.ask_widevine_install)
LOCAL_STATE_ON_VALUES=(true false)
LOCAL_STATE_OFF_VALUES=(false true)

# dotted JSON path in the profile Preferences file -> On/Off values (Off = upstream default)
PROFILE_KEYS=(browser.show_home_button brave.location_bar_is_wide omnibox.prevent_url_elisions brave.web_view_rounded_corners search.suggest_enabled brave.web_discovery_enabled)
PROFILE_ON_VALUES=(true true true true true true)
PROFILE_OFF_VALUES=(false false false true true false)

# Stable, version-independent link to the latest stable universal .dmg
# (GitHub's releases/latest/download redirect always resolves to the newest stable release).
BRAVE_DMG_URL="https://github.com/brave/brave-browser/releases/latest/download/Brave-Browser-universal.dmg"

is_brave_installed() {
    [[ -d "/Applications/Brave Browser.app" ]]
}

# Reads a line from the real terminal even when this script's own stdin is
# the curl|bash pipe (which is the script source, not the keyboard).
prompt_tty() {
    local prompt="$1" reply=""
    if [[ -r /dev/tty ]]; then
        read -r -p "$prompt" reply < /dev/tty
    fi
    echo "$reply"
}

run_as_user() {
    if [[ -n "${SUDO_USER:-}" ]]; then
        sudo -u "$SUDO_USER" -H "$@"
    else
        "$@"
    fi
}

find_brew() {
    if [[ -x /opt/homebrew/bin/brew ]]; then
        echo /opt/homebrew/bin/brew
    elif [[ -x /usr/local/bin/brew ]]; then
        echo /usr/local/bin/brew
    fi
}

install_brave() {
    if is_brave_installed; then return; fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "[DryRun] Brave not detected. Would prompt to install via Homebrew cask or direct .dmg download."
        return
    fi

    echo "Brave Browser was not found on this system."
    local reply
    reply="$(prompt_tty "Install it now? [Y/n] ")"
    if [[ "$reply" =~ ^[Nn] ]]; then
        echo "Skipping install. Policy settings will still be applied; profile preferences will be skipped until Brave has run at least once."
        return
    fi

    local method
    method="$(prompt_tty "Install via: [1] Homebrew cask (recommended)  [2] Direct .dmg download  Choice [1]: ")"
    [[ -z "$method" ]] && method="1"

    local brew_bin
    brew_bin="$(find_brew)"

    if [[ "$method" == "1" && -z "$brew_bin" ]]; then
        echo "Homebrew was not found for this user."
        local brew_reply
        brew_reply="$(prompt_tty "Install Homebrew now? [Y/n] ")"
        if [[ "$brew_reply" =~ ^[Nn] ]]; then
            echo "Falling back to direct .dmg download."
            method="2"
        else
            echo "Installing Homebrew (this can take a few minutes)..."
            run_as_user env NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            brew_bin="$(find_brew)"
        fi
    fi

    if [[ "$method" == "1" && -n "$brew_bin" ]]; then
        echo "Installing Brave via Homebrew cask..."
        run_as_user "$brew_bin" install --cask brave-browser
    else
        echo "Downloading Brave..."
        local dmg="/tmp/Brave-Browser.dmg"
        curl -fsSL -o "$dmg" "$BRAVE_DMG_URL"
        local mount_point
        mount_point="$(hdiutil attach "$dmg" -nobrowse -readonly | tail -1 | awk '{print $NF}')"
        echo "Installing to /Applications..."
        cp -R "$mount_point/Brave Browser.app" "/Applications/"
        hdiutil detach "$mount_point" -quiet || true
        rm -f "$dmg"
    fi

    if is_brave_installed; then
        echo "Brave installed successfully."
    else
        echo "Brave installation could not be confirmed. Policy settings will still be applied."
    fi
}

stop_brave() {
    if pgrep -x "Brave Browser" > /dev/null 2>&1; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            echo "[DryRun] Would quit Brave Browser."
        else
            echo "Closing Brave Browser to safely edit its JSON pref files..."
            pkill -x "Brave Browser" || true
            sleep 1
        fi
    fi
}

apply_policies() {
    if [[ "$DRY_RUN" -eq 0 ]]; then
        mkdir -p "/Library/Managed Preferences"
        [[ -f "$PLIST_PATH" ]] || /usr/bin/plutil -create xml1 "$PLIST_PATH"
    fi

    for i in "${!POLICY_NAMES[@]}"; do
        name="${POLICY_NAMES[$i]}"
        value="${POLICY_VALUES[$i]}"
        if [[ "$DRY_RUN" -eq 1 ]]; then
            echo "[DryRun] Would set $PLIST_PATH :$name = $value (bool)"
            continue
        fi
        "$PLIST_BUDDY" -c "Delete :$name" "$PLIST_PATH" >/dev/null 2>&1 || true
        "$PLIST_BUDDY" -c "Add :$name bool $value" "$PLIST_PATH"
        echo "Set $name = $value"
    done

    if [[ "$DRY_RUN" -eq 0 ]]; then
        chown root:wheel "$PLIST_PATH"
        chmod 644 "$PLIST_PATH"
        killall cfprefsd >/dev/null 2>&1 || true
    fi
}

remove_policies() {
    if [[ ! -f "$PLIST_PATH" ]]; then
        echo "No managed preferences file at $PLIST_PATH; nothing to remove."
        return
    fi

    for name in "${POLICY_NAMES[@]}"; do
        if [[ "$DRY_RUN" -eq 1 ]]; then
            echo "[DryRun] Would remove $PLIST_PATH :$name"
            continue
        fi
        "$PLIST_BUDDY" -c "Delete :$name" "$PLIST_PATH" >/dev/null 2>&1 || true
        echo "Removed $name"
    done

    if [[ "$DRY_RUN" -eq 0 ]]; then
        killall cfprefsd >/dev/null 2>&1 || true
    fi
}

real_user_home() {
    local target_user="${SUDO_USER:-}"
    if [[ -z "$target_user" ]]; then
        echo "$HOME"
        return
    fi
    dscl . -read "/Users/$target_user" NFSHomeDirectory | awk '{print $2}'
}

# Builds a flat JSON object string ({"dotted.path": value, ...}) from three
# global array *names* (passed as strings, since bash 3.2 has no namerefs)
# plus whether to use the On or Off value set.
build_mapping() {
    local keys_name="$1" on_name="$2" off_name="$3" enable="$4"
    eval "local keys=(\"\${${keys_name}[@]}\")"
    eval "local on_vals=(\"\${${on_name}[@]}\")"
    eval "local off_vals=(\"\${${off_name}[@]}\")"

    local mapping="{"
    local i v
    for i in "${!keys[@]}"; do
        if [[ "$enable" -eq 1 ]]; then v="${on_vals[$i]}"; else v="${off_vals[$i]}"; fi
        mapping+="\"${keys[$i]}\": $v,"
    done
    mapping="${mapping%,}}"
    echo "$mapping"
}

# Applies a flat {"dotted.path": value, ...} JSON mapping to a Brave JSON
# pref file (Local State or profile Preferences), merging into any existing
# nested structure without disturbing unrelated keys.
apply_json_prefs() {
    local path="$1" mapping="$2"

    if [[ ! -f "$path" ]]; then
        echo "Not found: $path (Brave may not be installed/run for this profile) - skipping."
        return
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "[DryRun] Would apply to $path:"
        echo "  $mapping"
        return
    fi

    local backup="${path}.bak"
    [[ -f "$backup" ]] || cp "$path" "$backup"

    python3 - "$path" "$mapping" <<'PYEOF'
import json
import sys

path, mapping_json = sys.argv[1], sys.argv[2]
mapping = json.loads(mapping_json)

with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

for dotted, value in mapping.items():
    node = data
    parts = dotted.split(".")
    for part in parts[:-1]:
        node = node.setdefault(part, {})
    node[parts[-1]] = value

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f)
PYEOF

    echo "Updated $path:"
    echo "  $mapping"
}

if [[ "$UNINSTALL" -eq 1 ]]; then
    ENABLE=0
    echo "Reverting Brave policy settings..."
else
    ENABLE=1
    echo "Applying Brave policy settings..."
fi

stop_brave

if [[ "$UNINSTALL" -eq 1 ]]; then
    remove_policies
else
    install_brave
    apply_policies
fi

HOME_DIR="$(real_user_home)"
LOCAL_STATE_PATH="$HOME_DIR/Library/Application Support/BraveSoftware/Brave-Browser/Local State"
PROFILE_PREFS_PATH="$HOME_DIR/Library/Application Support/BraveSoftware/Brave-Browser/Default/Preferences"

apply_json_prefs "$LOCAL_STATE_PATH" "$(build_mapping LOCAL_STATE_KEYS LOCAL_STATE_ON_VALUES LOCAL_STATE_OFF_VALUES "$ENABLE")"
apply_json_prefs "$PROFILE_PREFS_PATH" "$(build_mapping PROFILE_KEYS PROFILE_ON_VALUES PROFILE_OFF_VALUES "$ENABLE")"

if [[ "$DRY_RUN" -eq 0 ]]; then
    echo ""
    echo "Done. Start Brave and check:"
    echo "  brave://policy              (confirm the policies above are listed as 'Applied')"
    echo "  brave://settings/extensions (confirm Widevine is enabled)"
    echo "  brave://settings/appearance (confirm home button / wide address bar / full URLs / rounded corners)"
    echo "  brave://settings/search     (confirm search suggestions / web discovery)"
    echo ""
    echo "Not scripted (no safe pref/policy path - set these by hand once):"
    echo "  brave://settings/shields -> Block fingerprinting -> On"
    echo "  brave://settings/search  -> Default search engine (Normal and Private window) -> Brave"
fi

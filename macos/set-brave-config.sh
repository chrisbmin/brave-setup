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

is_brave_installed() {
    [[ -d "/Applications/Brave Browser.app" ]]
}

show_install_reminder() {
    if is_brave_installed; then return 0; fi

    echo ""
    echo "Brave Browser was not found on this system."
    echo "Download and install it from: https://brave.com/download/"
    echo "Launch Brave at least once, then re-run this script to apply settings."
    echo ""
    return 1
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
    if ! show_install_reminder; then
        exit 0
    fi
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

#!/usr/bin/env bash
#
# set-brave-config.sh
#
# Configures Brave Browser via the official enterprise managed-preferences
# plist (/Library/Managed Preferences/com.brave.Browser.plist) plus a small
# edit to the per-user Local State file for the one setting with no policy
# equivalent (Widevine). See ../policies-reference.md for the full list and
# sources.
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

if [[ "$EUID" -ne 0 ]]; then
    echo "This script needs administrator privileges to write Brave's managed preferences." >&2
    echo "Re-run as: curl -fsSL <url> | sudo bash" >&2
    exit 1
fi

PLIST_DOMAIN="com.brave.Browser"
PLIST_PATH="/Library/Managed Preferences/${PLIST_DOMAIN}.plist"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

# Parallel arrays (not an associative array - macOS ships bash 3.2, which lacks `declare -A`).
POLICY_NAMES=(BraveAIChatEnabled BraveWalletDisabled BraveRewardsDisabled BraveVPNDisabled BraveNewsDisabled BraveTalkDisabled PromotionalTabsEnabled)
POLICY_VALUES=(false true true true true true false)

stop_brave() {
    if pgrep -x "Brave Browser" > /dev/null 2>&1; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            echo "[DryRun] Would quit Brave Browser."
        else
            echo "Closing Brave Browser to safely edit its Local State file..."
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

set_widevine_prefs() {
    local enabled="$1"
    local home_dir
    home_dir="$(real_user_home)"
    local local_state="$home_dir/Library/Application Support/BraveSoftware/Brave-Browser/Local State"

    if [[ ! -f "$local_state" ]]; then
        echo "Local State not found at: $local_state (Brave may not be installed for this user) - skipping Widevine prefs."
        return
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "[DryRun] Would set brave.widevine_opted_in = $enabled and brave.ask_widevine_install = false in:"
        echo "  $local_state"
        return
    fi

    local backup="${local_state}.bak"
    [[ -f "$backup" ]] || cp "$local_state" "$backup"

    python3 - "$local_state" "$enabled" <<'PYEOF'
import json
import sys

path, enabled = sys.argv[1], sys.argv[2] == "true"

with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

brave = data.setdefault("brave", {})
brave["widevine_opted_in"] = enabled
brave["ask_widevine_install"] = False

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f)
PYEOF

    echo "Set brave.widevine_opted_in = $enabled in Local State"
}

if [[ "$UNINSTALL" -eq 1 ]]; then
    echo "Reverting Brave policy settings..."
    stop_brave
    remove_policies
    set_widevine_prefs "false"
else
    echo "Applying Brave policy settings..."
    stop_brave
    apply_policies
    set_widevine_prefs "true"
fi

if [[ "$DRY_RUN" -eq 0 ]]; then
    echo ""
    echo "Done. Start Brave and check:"
    echo "  brave://policy              (confirm the policies above are listed as 'Applied')"
    echo "  brave://settings/extensions (confirm Widevine is enabled)"
fi

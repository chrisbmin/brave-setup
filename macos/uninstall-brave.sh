#!/usr/bin/env bash
#
# uninstall-brave.sh
#
# Completely removes Brave Browser from this Mac: the application itself,
# all of its user data (bookmarks, passwords, history, extensions, profiles),
# and every setting applied by set-brave-config.sh (the managed-preferences
# plist, Local State / profile Preferences edits).
#
# This is destructive and irreversible - it deletes your Brave profile data.
# Requires typed "YES" confirmation unless --force is passed.
#
# Usage:
#   curl -fsSL <raw-url-to-this-file> | sudo bash
#   curl -fsSL <raw-url-to-this-file> | sudo bash -s -- --dry-run
#   curl -fsSL <raw-url-to-this-file> | sudo bash -s -- --force   # skip the typed confirmation

set -euo pipefail

FORCE=0
DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --force) FORCE=1 ;;
        --dry-run) DRY_RUN=1 ;;
        *) echo "Unknown argument: $arg" >&2; exit 1 ;;
    esac
done

if [[ "$DRY_RUN" -eq 0 && "$EUID" -ne 0 ]]; then
    echo "This script needs administrator privileges to fully remove Brave." >&2
    echo "Re-run as: curl -fsSL <url> | sudo bash" >&2
    exit 1
fi

PLIST_PATH="/Library/Managed Preferences/com.brave.Browser.plist"
POLICY_NAMES=(BraveAIChatEnabled BraveWalletDisabled BraveRewardsDisabled BraveVPNDisabled BraveNewsDisabled BraveTalkDisabled PromotionalTabsEnabled)

prompt_tty() {
    local prompt="$1" reply=""
    if [[ -r /dev/tty ]]; then
        read -r -p "$prompt" reply < /dev/tty
    fi
    echo "$reply"
}

confirm_destructive() {
    if [[ "$FORCE" -eq 1 || "$DRY_RUN" -eq 1 ]]; then return 0; fi

    echo ""
    echo "WARNING: this will COMPLETELY remove Brave Browser from this Mac,"
    echo "including ALL of its data: bookmarks, saved passwords, browsing history,"
    echo "and extensions. This cannot be undone."
    echo ""
    local reply
    reply="$(prompt_tty 'Type YES (all caps) to continue: ')"
    [[ "$reply" == "YES" ]]
}

real_user_home() {
    local target_user="${SUDO_USER:-}"
    if [[ -z "$target_user" ]]; then
        echo "$HOME"
        return
    fi
    dscl . -read "/Users/$target_user" NFSHomeDirectory | awk '{print $2}'
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

stop_brave() {
    if pgrep -x "Brave Browser" > /dev/null 2>&1; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            echo "[DryRun] Would quit Brave Browser."
        else
            echo "Closing Brave Browser..."
            pkill -x "Brave Browser" || true
            sleep 1
        fi
    fi
}

remove_policies() {
    if [[ ! -f "$PLIST_PATH" ]]; then return; fi
    for name in "${POLICY_NAMES[@]}"; do
        if [[ "$DRY_RUN" -eq 1 ]]; then
            echo "[DryRun] Would remove $PLIST_PATH :$name"
            continue
        fi
        "/usr/libexec/PlistBuddy" -c "Delete :$name" "$PLIST_PATH" >/dev/null 2>&1 || true
        echo "Removed policy $name"
    done
    if [[ "$DRY_RUN" -eq 0 ]]; then
        killall cfprefsd >/dev/null 2>&1 || true
    fi
}

uninstall_brave_app() {
    local brew_bin
    brew_bin="$(find_brew)"

    if [[ -n "$brew_bin" ]] && run_as_user "$brew_bin" list --cask brave-browser > /dev/null 2>&1; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            echo "[DryRun] Would run: brew uninstall --cask brave-browser --zap"
        else
            echo "Uninstalling Brave via Homebrew..."
            run_as_user "$brew_bin" uninstall --cask brave-browser --zap || true
        fi
    elif [[ -d "/Applications/Brave Browser.app" ]]; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            echo "[DryRun] Would delete: /Applications/Brave Browser.app"
        else
            rm -rf "/Applications/Brave Browser.app"
            echo "Deleted: /Applications/Brave Browser.app"
        fi
    fi
}

remove_leftover_data() {
    local home_dir
    home_dir="$(real_user_home)"

    local paths=(
        "$home_dir/Library/Application Support/BraveSoftware"
        "$home_dir/Library/Caches/BraveSoftware"
        "$home_dir/Library/Logs/BraveSoftware"
        "$home_dir/Library/Preferences/com.brave.Browser.plist"
        "$home_dir/Library/Saved Application State/com.brave.Browser.savedState"
    )

    for path in "${paths[@]}"; do
        if [[ ! -e "$path" ]]; then continue; fi
        if [[ "$DRY_RUN" -eq 1 ]]; then
            echo "[DryRun] Would delete: $path"
        else
            rm -rf "$path"
            echo "Deleted: $path"
        fi
    done

    # HTTPStorages is named with the bundle id plus a per-container suffix - glob for it.
    for path in "$home_dir/Library/HTTPStorages/com.brave.Browser"*; do
        [[ -e "$path" ]] || continue
        if [[ "$DRY_RUN" -eq 1 ]]; then
            echo "[DryRun] Would delete: $path"
        else
            rm -rf "$path"
            echo "Deleted: $path"
        fi
    done
}

if ! confirm_destructive; then
    echo "Cancelled. Nothing was changed."
    exit 0
fi

stop_brave
remove_policies
uninstall_brave_app
remove_leftover_data

if [[ "$DRY_RUN" -eq 0 ]]; then
    echo ""
    echo "Done. Brave Browser and its settings/data have been removed."
fi

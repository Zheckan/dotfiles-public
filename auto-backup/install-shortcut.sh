#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/.." && pwd)/_helpers.sh"

log_section "Auto-Backup Apple Shortcut — Setup"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SHORTCUT_NAME="Dotfiles Backup"
DOTFILES_REPO_DIR="${DOTFILES_REPO_DIR:-$DOTFILES_DIR}"

# Check if Shortcuts CLI is available (macOS 12+)
if ! command_exists shortcuts; then
  log_error "Shortcuts CLI not available. Requires macOS 12 Monterey or later."
  exit 1
fi

# Check if shortcut already exists
if shortcuts list | grep -q "^${SHORTCUT_NAME}$"; then
  log_info "Shortcut '$SHORTCUT_NAME' already exists."
else
  # Import the shortcut from the .shortcut file
  SHORTCUT_FILE="$SCRIPT_DIR/Dotfiles Backup.shortcut"
  if [[ -f "$SHORTCUT_FILE" ]]; then
    shortcuts import "$SHORTCUT_FILE"
    log_info "Imported '$SHORTCUT_NAME' shortcut."
  else
    log_warn "No .shortcut file found. Creating shortcut manually..."
    log_manual "Create the shortcut manually in the Shortcuts app:"
    log_manual ""
    log_manual "  1. Open Shortcuts.app"
    log_manual "  2. Click '+' to create a new shortcut"
    log_manual "  3. Name it: $SHORTCUT_NAME"
    log_manual "  4. Add action: 'Run Shell Script'"
    log_manual "  5. Set shell to: /bin/bash"
    log_manual "  6. Paste this script:"
    log_manual "     export DOTFILES_REPO_DIR=\"$DOTFILES_REPO_DIR\""
    log_manual "     \"\$DOTFILES_REPO_DIR/auto-backup/run-backup.sh\""
    log_manual ""
    log_manual "  If this is your main PC, use this instead:"
    log_manual "     export DOTFILES_REPO_DIR=\"$DOTFILES_REPO_DIR\""
    log_manual "     \"\$DOTFILES_REPO_DIR/auto-backup/run-backup.sh\" --main-pc"
    log_manual ""
    log_manual "  To schedule it (Automation):"
    log_manual "  7. Go to the Automations tab"
    log_manual "  8. Click '+' → 'Time of Day'"
    log_manual "  9. Set to run daily (or pick specific days)"
    log_manual " 10. Action: 'Run Shortcut' → select '$SHORTCUT_NAME'"
    log_manual " 11. Toggle OFF 'Ask Before Running'"
    print_manual_steps
    exit 0
  fi
fi

log_info ""
log_info "Next steps:"
log_info "  1. Open Shortcuts.app → Automations tab"
log_info "  2. Click '+' → 'Time of Day'"
log_info "  3. Set your preferred schedule (e.g. daily at 2 AM, or specific days)"
log_info "  4. Action: 'Run Shortcut' → select '$SHORTCUT_NAME'"
log_info "  5. Toggle OFF 'Ask Before Running' for silent execution"
log_info ""
log_info "Note: The script auto-detects device and commits to a device-specific branch."
log_info "  Add --main-pc to the script in your shortcut if this is your primary machine."
log_info "  This will also create a PR and merge changes to main."
log_info ""
log_info "You can also run the shortcut manually anytime:"
log_info "  shortcuts run '$SHORTCUT_NAME'"
log_info "  — or from the menu bar / Dock if you add it there"

log_manual "Set up a Shortcuts Automation to schedule '$SHORTCUT_NAME' (see steps above)"
print_manual_steps

#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../.." && pwd)/_helpers.sh"

log_section "Misc — Install"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

"$SCRIPT_DIR/gh/install.sh"
"$SCRIPT_DIR/mise/install.sh"
"$SCRIPT_DIR/mactop/install.sh"

# Clean up reverted logitech-keyremap module (PR #67 → reverted in PR #69)
KEYREMAP_PLIST="$HOME/Library/LaunchAgents/com.logitech.keyremap.plist"
if [[ -f "$KEYREMAP_PLIST" ]]; then
  log_info "Unloading and removing leftover logitech-keyremap LaunchAgent..."
  launchctl unload "$KEYREMAP_PLIST" 2>/dev/null || true
  rm -f "$KEYREMAP_PLIST"
  rm -f "$HOME/.config/logitech-keyremap" "$HOME/.config/logitech-keyremap.swift"
  log_info "Logitech keyremap cleanup complete"
fi

print_manual_steps

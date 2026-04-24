#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/.." && pwd)/_helpers.sh"

log_section "Auto-Backup LaunchAgent — Uninstall"

PLIST_DEST="$HOME/Library/LaunchAgents/com.dotfiles.autocommit.plist"

if [[ -f "$PLIST_DEST" ]]; then
  launchctl unload "$PLIST_DEST"
  rm "$PLIST_DEST"
  log_info "Auto-backup LaunchAgent removed"
else
  log_warn "LaunchAgent plist not found — nothing to uninstall."
fi

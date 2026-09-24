#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../.." && pwd)/_helpers.sh"

log_section "Raycast — Install"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RAYCAST_EXPORT_DIR="$HOME/Library/Application Support/dotfiles/raycast-exports"

# Raycast only imports through its UI, so nothing is copied to the system here.
ensure_dir "$RAYCAST_EXPORT_DIR"

if [[ -f "$SCRIPT_DIR/Raycast.rayconfig" ]]; then
  log_manual "Import $SCRIPT_DIR/Raycast.rayconfig via Raycast → Settings → Advanced → Import (enter the export password)"
fi
log_manual "Set Raycast's scheduled export (Settings → Advanced) to save password-protected exports into $RAYCAST_EXPORT_DIR"

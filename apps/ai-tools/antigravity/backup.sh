#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"

log_section "Antigravity CLI — Backup"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ANTIGRAVITY_CONFIG_DIR="$HOME/.antigravity"

copy_to_repo "$ANTIGRAVITY_CONFIG_DIR/settings.json" "$SCRIPT_DIR/settings.json"
copy_to_repo "$ANTIGRAVITY_CONFIG_DIR/statusline.sh" "$SCRIPT_DIR/statusline.sh"
copy_to_repo "$ANTIGRAVITY_CONFIG_DIR/debug_statusline.sh" "$SCRIPT_DIR/debug_statusline.sh"

sync_dir_to_repo "$ANTIGRAVITY_CONFIG_DIR/skills" "$SCRIPT_DIR/skills"

# Never backed up: brain/ (per-session runtime), last_payload.json (ephemeral)

log_info "Antigravity CLI config backed up."

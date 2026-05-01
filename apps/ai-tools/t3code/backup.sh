#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"

log_section "T3 Code — Backup"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
T3_CONFIG_DIR="$HOME/.t3"
T3_USERDATA_DIR="$T3_CONFIG_DIR/userdata"

copy_to_repo "$T3_USERDATA_DIR/client-settings.json" "$SCRIPT_DIR/userdata/client-settings.json"
copy_to_repo "$T3_USERDATA_DIR/settings.json" "$SCRIPT_DIR/userdata/settings.json"
copy_to_repo "$T3_USERDATA_DIR/keybindings.json" "$SCRIPT_DIR/userdata/keybindings.json"

# Never backed up: caches/, worktrees/, userdata/attachments/,
# userdata/logs/, userdata/secrets/, userdata/state.sqlite*,
# userdata/environment-id, userdata/server-runtime.json

log_info "T3 Code config backed up."

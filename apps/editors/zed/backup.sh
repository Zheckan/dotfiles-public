#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"

log_section "Zed — Backup"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZED_CONFIG_DIR="$HOME/.config/zed"

copy_to_repo "$ZED_CONFIG_DIR/settings.json" "$SCRIPT_DIR/settings.json"

log_info "Zed config backed up."

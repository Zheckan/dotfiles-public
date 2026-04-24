#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../.." && pwd)/_helpers.sh"

log_section "MultiViewer for F1 — Install"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MV_CONFIG_DIR="$HOME/Library/Application Support/MultiViewer"

ensure_dir "$MV_CONFIG_DIR"

copy_to_system "$SCRIPT_DIR/config.json"         "$MV_CONFIG_DIR/config.json"
copy_to_system "$SCRIPT_DIR/setups.config.json"   "$MV_CONFIG_DIR/setups.config.json"
copy_to_system "$SCRIPT_DIR/setups.schema.json"   "$MV_CONFIG_DIR/setups.schema.json"
copy_to_system "$SCRIPT_DIR/config.ota.json"      "$MV_CONFIG_DIR/config.ota.json"

log_info "MultiViewer for F1 config restored."

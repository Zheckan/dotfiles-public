#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"

log_section "Ghostty — Backup"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GHOSTTY_CONFIG_DIR="$HOME/Library/Application Support/com.mitchellh.ghostty"

copy_to_repo "$GHOSTTY_CONFIG_DIR/config" "$SCRIPT_DIR/config"

log_info "Ghostty config backed up."

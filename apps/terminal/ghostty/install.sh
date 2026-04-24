#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"

log_section "Ghostty — Install"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GHOSTTY_CONFIG_DIR="$HOME/Library/Application Support/com.mitchellh.ghostty"

copy_to_system "$SCRIPT_DIR/config" "$GHOSTTY_CONFIG_DIR/config"

log_info "Ghostty config installed."

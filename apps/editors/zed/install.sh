#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"

log_section "Zed — Install"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZED_CONFIG_DIR="$HOME/.config/zed"

copy_to_system "$SCRIPT_DIR/settings.json" "$ZED_CONFIG_DIR/settings.json"

log_info "Zed config installed."

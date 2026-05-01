#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"

log_section "T3 Code — Install"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
T3_CONFIG_DIR="$HOME/.t3"
T3_USERDATA_DIR="$T3_CONFIG_DIR/userdata"

copy_to_system "$SCRIPT_DIR/userdata/client-settings.json" "$T3_USERDATA_DIR/client-settings.json"
copy_to_system "$SCRIPT_DIR/userdata/settings.json" "$T3_USERDATA_DIR/settings.json"
copy_to_system "$SCRIPT_DIR/userdata/keybindings.json" "$T3_USERDATA_DIR/keybindings.json"

log_manual "Launch T3 Code once to regenerate runtime state"

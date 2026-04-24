#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"

log_section "Gemini CLI — Install"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GEMINI_CONFIG_DIR="$HOME/.gemini"

# Copy config files
copy_to_system "$SCRIPT_DIR/settings.json" "$GEMINI_CONFIG_DIR/settings.json"
copy_to_system "$SCRIPT_DIR/settings.json.orig" "$GEMINI_CONFIG_DIR/settings.json.orig"

log_manual "Run 'gemini' to authenticate with Google"

#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"

log_section "GitHub CLI — Install"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

copy_to_system "$SCRIPT_DIR/config.yml" "$HOME/.config/gh/config.yml"

log_manual "Run 'gh auth login' to authenticate"

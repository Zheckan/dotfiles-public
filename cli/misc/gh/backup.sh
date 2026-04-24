#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"

log_section "GitHub CLI — Backup"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

copy_to_repo "$HOME/.config/gh/config.yml" "$SCRIPT_DIR/config.yml"

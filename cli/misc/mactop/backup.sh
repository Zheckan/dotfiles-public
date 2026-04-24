#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"

log_section "Mactop — Backup"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

copy_to_repo "$HOME/.mactop/config.json" "$SCRIPT_DIR/config.json"

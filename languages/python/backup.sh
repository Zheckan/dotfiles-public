#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../.." && pwd)/_helpers.sh"

log_section "Python — Backup"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

copy_to_repo "$HOME/.condarc" "$SCRIPT_DIR/.condarc"

log_info "Python config backed up."

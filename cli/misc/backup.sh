#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../.." && pwd)/_helpers.sh"

log_section "Misc — Backup"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

"$SCRIPT_DIR/gh/backup.sh"
"$SCRIPT_DIR/mise/backup.sh"
"$SCRIPT_DIR/mactop/backup.sh"

log_info "All misc configs backed up."

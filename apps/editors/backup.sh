#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../.." && pwd)/_helpers.sh"

log_section "Editors — Backup"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

"$SCRIPT_DIR/cursor/backup.sh"
"$SCRIPT_DIR/vscode/backup.sh"
"$SCRIPT_DIR/zed/backup.sh"

log_info "All editor configs backed up."

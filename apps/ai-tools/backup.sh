#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../.." && pwd)/_helpers.sh"

log_section "AI Tools — Backup"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

"$SCRIPT_DIR/claude/backup.sh"
"$SCRIPT_DIR/codex/backup.sh"
"$SCRIPT_DIR/gemini/backup.sh"
"$SCRIPT_DIR/opencode/backup.sh"

log_info "All AI tool configs backed up."

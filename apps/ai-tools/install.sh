#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../.." && pwd)/_helpers.sh"

log_section "AI Tools — Install"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

"$SCRIPT_DIR/claude/install.sh"
"$SCRIPT_DIR/codex/install.sh"
"$SCRIPT_DIR/gemini/install.sh"
"$SCRIPT_DIR/opencode/install.sh"

print_manual_steps

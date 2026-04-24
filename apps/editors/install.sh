#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../.." && pwd)/_helpers.sh"

log_section "Editors — Install"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

"$SCRIPT_DIR/cursor/install.sh"
"$SCRIPT_DIR/vscode/install.sh"
"$SCRIPT_DIR/zed/install.sh"

print_manual_steps

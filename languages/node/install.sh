#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../.." && pwd)/_helpers.sh"

log_section "Node.js Ecosystem — Install"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

"$SCRIPT_DIR/nvm/install.sh"
"$SCRIPT_DIR/bun/install.sh"
"$SCRIPT_DIR/pnpm/install.sh"
"$SCRIPT_DIR/yarn/install.sh"
"$SCRIPT_DIR/globals/install.sh"

print_manual_steps

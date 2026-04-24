#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../.." && pwd)/_helpers.sh"

log_section "Python — Install"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Copy conda config
copy_to_system "$SCRIPT_DIR/.condarc" "$HOME/.condarc"

"$SCRIPT_DIR/conda/install.sh"
"$SCRIPT_DIR/globals/install.sh"

log_manual "Install Miniconda/Anaconda via the official .pkg installer from https://docs.conda.io"

print_manual_steps

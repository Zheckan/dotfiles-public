#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"

log_section "Conda — Install"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# This is a duplicate of python's condarc for organizational reasons,
# but both point to the same file (~/.condarc)
copy_to_system "$SCRIPT_DIR/.condarc" "$HOME/.condarc"

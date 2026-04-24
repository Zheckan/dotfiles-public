#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

log_section "Python Global Packages — Backup"

if ! command_exists pip; then
  log_warn "pip not found — skipping"
  return 0 2>/dev/null || exit 0
fi

# Export user-installed packages (exclude Anaconda/system bundled ones)
# We maintain this list manually — add packages you want on a new machine
log_info "pip-globals.txt is maintained manually."
log_info "To add a package: append its name to pip-globals.txt"

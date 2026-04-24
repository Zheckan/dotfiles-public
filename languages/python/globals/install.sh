#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

log_section "Python Global Packages"

GLOBALS_FILE="$SCRIPT_DIR/pip-globals.txt"

if ! command_exists pip; then
  log_warn "pip not found — skipping global packages (run after Conda is installed)"
  return 0 2>/dev/null || exit 0
fi

if [[ ! -f "$GLOBALS_FILE" ]]; then
  log_warn "No pip-globals.txt found — skipping"
  return 0 2>/dev/null || exit 0
fi

while IFS= read -r package || [[ -n "$package" ]]; do
  package=$(echo "$package" | xargs)
  [[ -z "$package" || "$package" == \#* ]] && continue
  if pip show "$package" &>/dev/null; then
    log_info "$package already installed"
  else
    log_info "Installing $package..."
    pip install "$package"
  fi
done < "$GLOBALS_FILE"

#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"

log_section "Node Global Packages — Install"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GLOBALS_FILE="$SCRIPT_DIR/npm-globals.txt"

if [[ ! -f "$GLOBALS_FILE" ]]; then
  log_warn "npm-globals.txt not found — skipping global package install."
  exit 0
fi

require_command npm

log_info "Installing global npm packages from npm-globals.txt..."
while IFS= read -r pkg || [[ -n "$pkg" ]]; do
  # Skip blank lines and comments
  [[ -z "$pkg" || "$pkg" == \#* ]] && continue
  log_info "Installing: $pkg"
  npm install -g "$pkg" || log_warn "Failed to install: $pkg"
done < "$GLOBALS_FILE"

log_info "Global npm packages installed."

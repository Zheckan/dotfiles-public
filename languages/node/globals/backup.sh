#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"

log_section "Node Global Packages — Backup"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GLOBALS_FILE="$SCRIPT_DIR/npm-globals.txt"

# Start with an empty file
> "$GLOBALS_FILE"

# Export npm global packages (preserves @scope/name format)
if command_exists npm; then
  log_info "Exporting npm global packages..."
  npm list -g --depth=0 2>/dev/null | tail -n +2 | sed 's/.*[├└]── //' | sed 's/@[0-9].*//' >> "$GLOBALS_FILE"
else
  log_warn "npm not found — skipping npm globals export."
fi

# Append pnpm global packages if pnpm is available
if command_exists pnpm; then
  log_info "Exporting pnpm global packages..."
  pnpm list -g 2>/dev/null | grep -E '^(│|├|└)' | sed 's/.*[├└]── //' | sed 's/ .*//' >> "$GLOBALS_FILE"
else
  log_info "pnpm not found — skipping pnpm globals export."
fi

# Remove duplicates, empty lines, and sort
if [[ -f "$GLOBALS_FILE" ]]; then
  grep -v '^$' "$GLOBALS_FILE" | sort -u > "$GLOBALS_FILE.tmp" && mv "$GLOBALS_FILE.tmp" "$GLOBALS_FILE"
  log_info "Global packages list saved to npm-globals.txt"
fi

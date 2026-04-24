#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

log_section "OpenCode Backup"

copy_to_repo "$HOME/.config/opencode/opencode.json" "$SCRIPT_DIR/opencode.json"

# Backup instructions
if [[ -d "$HOME/.config/opencode/instructions" ]]; then
  ensure_dir "$SCRIPT_DIR/instructions"
  for f in "$HOME/.config/opencode/instructions"/*; do
    [[ -f "$f" ]] && cp "$f" "$SCRIPT_DIR/instructions/"
  done
  log_info "Backed up OpenCode instructions"
fi

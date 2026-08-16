#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

log_section "OpenCode Backup"

# ── Config (sanitized) ───────────────────────────────────────────────
# opencode.json stores MCP auth material inline — a live Context7 API key
# reached this repo because the file used to be copied verbatim. Fail closed:
# if the sanitizer cannot run, keep the previous repo copy rather than commit
# a raw secret.
OPENCODE_CONFIG="$HOME/.config/opencode/opencode.json"
CONFIG_SANITIZER="$SCRIPT_DIR/sanitize-config.py"
SANITIZE_FAILED=false

if [[ -f "$OPENCODE_CONFIG" ]]; then
  if command_exists python3; then
    tmp="$(mktemp)"
    if python3 "$CONFIG_SANITIZER" "$OPENCODE_CONFIG" "$tmp"; then
      mv "$tmp" "$SCRIPT_DIR/opencode.json"
      log_info "Backed up opencode.json (inline credentials → {env:...} references)"
    else
      rm -f "$tmp"
      SANITIZE_FAILED=true
      log_error "sanitize-config.py failed — refusing to back up opencode.json with possible inline secrets"
    fi
  else
    SANITIZE_FAILED=true
    log_error "python3 not found — refusing to back up opencode.json unsanitized"
  fi
else
  log_warn "Source not found: $OPENCODE_CONFIG (skipping)"
fi

# Backup instructions
if [[ -d "$HOME/.config/opencode/instructions" ]]; then
  ensure_dir "$SCRIPT_DIR/instructions"
  for f in "$HOME/.config/opencode/instructions"/*; do
    [[ -f "$f" ]] && cp "$f" "$SCRIPT_DIR/instructions/"
  done
  log_info "Backed up OpenCode instructions"
fi

# Surface a refused config backup as a module failure so the master run warns.
if [[ "$SANITIZE_FAILED" == true ]]; then
  exit 1
fi

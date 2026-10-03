#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"

log_section "Pi — Backup"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PI_CONFIG_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"

if [[ ! -d "$PI_CONFIG_DIR" ]]; then
  log_info "Pi config not found at $PI_CONFIG_DIR (skipping)."
  exit 0
fi

# Nothing reaches the committed snapshot until every selected file is prepared.
require_command python3
require_command rsync
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
if ! python3 "$SCRIPT_DIR/prepare-backup.py" "$PI_CONFIG_DIR" "$stage"; then
  log_error "Pi backup refused; previous snapshot kept. See errors above."
  exit 1
fi
ensure_dir "$SCRIPT_DIR/config"
rsync -ac --delete "$stage/" "$SCRIPT_DIR/config/"
log_info "Pi reusable config backed up; credentials, sessions, and runtime excluded."

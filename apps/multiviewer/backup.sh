#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../.." && pwd)/_helpers.sh"

log_section "MultiViewer for F1 — Backup"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MV_CONFIG_DIR="$HOME/Library/Application Support/MultiViewer"

copy_to_repo "$MV_CONFIG_DIR/config.json"         "$SCRIPT_DIR/config.json"
copy_to_repo "$MV_CONFIG_DIR/setups.config.json"   "$SCRIPT_DIR/setups.config.json"
copy_to_repo "$MV_CONFIG_DIR/setups.schema.json"   "$SCRIPT_DIR/setups.schema.json"
copy_to_repo "$MV_CONFIG_DIR/config.ota.json"      "$SCRIPT_DIR/config.ota.json"

# Strip analyticsUserId from backed-up config to avoid leaking a personal identifier
if [[ -f "$SCRIPT_DIR/config.json" ]] && command -v python3 &>/dev/null; then
  python3 -c "
import json, sys
path = sys.argv[1]
with open(path) as f: data = json.load(f)
data['analyticsUserId'] = ''
with open(path, 'w') as f: json.dump(data, f, indent=2)
" "$SCRIPT_DIR/config.json"
  log_info "Stripped analyticsUserId from config.json"
fi

log_info "MultiViewer for F1 config backed up."

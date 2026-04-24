#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"

log_section "Gemini CLI — Backup"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GEMINI_CONFIG_DIR="$HOME/.gemini"

copy_to_repo "$GEMINI_CONFIG_DIR/settings.json" "$SCRIPT_DIR/settings.json"
copy_to_repo "$GEMINI_CONFIG_DIR/settings.json.orig" "$SCRIPT_DIR/settings.json.orig"

# Never backed up: oauth_creds.json, google_accounts.json,
# installation_id, user_id, google_account_id, state.json, tmp/

log_info "Gemini CLI config backed up."

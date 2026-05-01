#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"

log_section "Gemini CLI — Backup"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GEMINI_CONFIG_DIR="$HOME/.gemini"

copy_to_repo "$GEMINI_CONFIG_DIR/settings.json" "$SCRIPT_DIR/settings.json"
copy_to_repo "$GEMINI_CONFIG_DIR/settings.json.orig" "$SCRIPT_DIR/settings.json.orig"
copy_to_repo "$GEMINI_CONFIG_DIR/GEMINI.md" "$SCRIPT_DIR/GEMINI.md"

sync_dir_to_repo "$GEMINI_CONFIG_DIR/commands" "$SCRIPT_DIR/commands"
sync_dir_to_repo "$GEMINI_CONFIG_DIR/policies" "$SCRIPT_DIR/policies"
sync_dir_to_repo "$GEMINI_CONFIG_DIR/skills" "$SCRIPT_DIR/skills"

# Never backed up: oauth_creds.json, google_accounts.json,
# installation_id, user_id, google_account_id, state.json,
# projects.json, trustedFolders.json, history/, tmp/

log_info "Gemini CLI config backed up."

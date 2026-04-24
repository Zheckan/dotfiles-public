#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"

log_section "Codex CLI — Backup"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CODEX_CONFIG_DIR="$HOME/.codex"

# ── Config files (explicit whitelist) ────────────────────────────────
copy_to_repo "$CODEX_CONFIG_DIR/config.toml"             "$SCRIPT_DIR/config.toml"
copy_to_repo "$CODEX_CONFIG_DIR/config.json"              "$SCRIPT_DIR/config.json"
copy_to_repo "$CODEX_CONFIG_DIR/instructions.md"          "$SCRIPT_DIR/instructions.md"
copy_to_repo "$CODEX_CONFIG_DIR/AGENTS.md"                "$SCRIPT_DIR/AGENTS.md"
# ── User-content directories (full sync) ─────────────────────────────
sync_dir_to_repo "$CODEX_CONFIG_DIR/rules" "$SCRIPT_DIR/rules"

# Skills: sync only user-created skills (exclude .system/)
if [[ -d "$CODEX_CONFIG_DIR/skills" ]]; then
  ensure_dir "$SCRIPT_DIR/skills"
  rsync -a --delete --exclude='.DS_Store' --exclude='.system/' "$CODEX_CONFIG_DIR/skills/" "$SCRIPT_DIR/skills/"
  log_info "Synced $CODEX_CONFIG_DIR/skills → $SCRIPT_DIR/skills (excluding .system/)"
fi

# ── Never backed up ──────────────────────────────────────────────────
# auth.json, sessions/, archived_sessions/, history.jsonl,
# tmp/, log/, sqlite/, shell_snapshots/, vendor_imports/,
# models_cache.json, update-check.json, version.json,
# .codex-global-state.json, internal_storage.json, .personality_migration

log_info "Codex CLI config backed up."

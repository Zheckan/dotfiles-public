#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"

log_section "Codex CLI — Backup"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CODEX_CONFIG_DIR="$HOME/.codex"

# ── Config files (explicit whitelist) ────────────────────────────────
# config.toml is sanitized to drop [marketplaces.*] last_updated/last_revision,
# which Codex rewrites on every marketplace re-sync and which caused a daily
# no-op backup commit. Real settings still come through verbatim.
CONFIG_SANITIZER="$SCRIPT_DIR/sanitize-config.py"
if [[ -f "$CODEX_CONFIG_DIR/config.toml" ]] && command_exists python3; then
  tmp="$(mktemp)"
  if python3 "$CONFIG_SANITIZER" "$CODEX_CONFIG_DIR/config.toml" "$tmp"; then
    mv "$tmp" "$SCRIPT_DIR/config.toml"
    log_info "Backed up config.toml (stripped marketplace refresh pointers)"
  else
    rm -f "$tmp"
    copy_to_repo "$CODEX_CONFIG_DIR/config.toml" "$SCRIPT_DIR/config.toml"
    log_warn "sanitize-config.py failed — backed up config.toml as-is"
  fi
else
  copy_to_repo "$CODEX_CONFIG_DIR/config.toml"           "$SCRIPT_DIR/config.toml"
fi
copy_to_repo "$CODEX_CONFIG_DIR/config.json"              "$SCRIPT_DIR/config.json"
copy_to_repo "$CODEX_CONFIG_DIR/instructions.md"          "$SCRIPT_DIR/instructions.md"
copy_to_repo "$CODEX_CONFIG_DIR/AGENTS.md"                "$SCRIPT_DIR/AGENTS.md"
# ── User-content directories (full sync) ─────────────────────────────
sync_dir_to_repo "$CODEX_CONFIG_DIR/rules" "$SCRIPT_DIR/rules"
sync_dir_to_repo "$CODEX_CONFIG_DIR/agents" "$SCRIPT_DIR/agents"
sync_dir_to_repo "$CODEX_CONFIG_DIR/pets" "$SCRIPT_DIR/pets"

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

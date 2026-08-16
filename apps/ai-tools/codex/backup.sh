#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"

log_section "Codex CLI — Backup"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CODEX_CONFIG_DIR="$HOME/.codex"

# ── Config files (explicit whitelist) ────────────────────────────────
# config.toml is sanitized to drop [marketplaces.*] last_updated/last_revision,
# which Codex rewrites on every marketplace re-sync and which caused a daily
# no-op backup commit, and to redact inline MCP credentials. Real settings still
# come through verbatim.
#
# Fail closed: config.toml carries a Context7 API key inline, so falling back to
# an as-is copy when the sanitizer cannot run would commit that secret. Keep the
# previous repo copy instead.
CONFIG_SANITIZER="$SCRIPT_DIR/sanitize-config.py"
SANITIZE_FAILED=false

if [[ -f "$CODEX_CONFIG_DIR/config.toml" ]]; then
  if command_exists python3; then
    tmp="$(mktemp)"
    if python3 "$CONFIG_SANITIZER" "$CODEX_CONFIG_DIR/config.toml" "$tmp"; then
      mv "$tmp" "$SCRIPT_DIR/config.toml"
      log_info "Backed up config.toml (marketplace pointers stripped, credentials redacted)"
    else
      rm -f "$tmp"
      SANITIZE_FAILED=true
      log_error "sanitize-config.py failed — refusing to back up config.toml with inline secrets"
    fi
  else
    SANITIZE_FAILED=true
    log_error "python3 not found — refusing to back up config.toml unsanitized"
  fi
else
  log_warn "Source not found: $CODEX_CONFIG_DIR/config.toml (skipping)"
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

# Surface a refused config backup as a module failure so the master run warns.
if [[ "$SANITIZE_FAILED" == true ]]; then
  exit 1
fi

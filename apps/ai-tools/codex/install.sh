#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"

log_section "Codex CLI — Install"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CODEX_CONFIG_DIR="$HOME/.codex"

# Install Codex if missing
if command_exists codex; then
  log_info "Codex CLI is already installed."
else
  if command_exists npm; then
    log_info "Installing Codex CLI via npm..."
    npm install -g @openai/codex
  else
    log_manual "Install Codex CLI: npm install -g @openai/codex (npm not yet available — run after languages/node/install.sh)"
  fi
fi

# ── Config files ─────────────────────────────────────────────────────
copy_to_system "$SCRIPT_DIR/config.toml"             "$CODEX_CONFIG_DIR/config.toml"
copy_to_system "$SCRIPT_DIR/config.json"              "$CODEX_CONFIG_DIR/config.json"
copy_to_system "$SCRIPT_DIR/instructions.md"          "$CODEX_CONFIG_DIR/instructions.md"
copy_to_system "$SCRIPT_DIR/AGENTS.md"                "$CODEX_CONFIG_DIR/AGENTS.md"
# ── User-content directories ─────────────────────────────────────────
sync_dir_to_system "$SCRIPT_DIR/rules" "$CODEX_CONFIG_DIR/rules"

if [[ -d "$SCRIPT_DIR/skills" ]]; then
  ensure_dir "$CODEX_CONFIG_DIR/skills"
  rsync -a --exclude='.DS_Store' "$SCRIPT_DIR/skills/" "$CODEX_CONFIG_DIR/skills/"
  log_info "Restored $SCRIPT_DIR/skills → $CODEX_CONFIG_DIR/skills"
fi

log_manual "Run 'codex' to authenticate with OpenAI"

#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"

log_section "Antigravity CLI — Backup"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ANTIGRAVITY_SUPPORT_DIR="$HOME/.antigravity"
AGY_CONFIG_DIR="$HOME/.gemini/antigravity-cli"
ANTIGRAVITY_GLOBAL_CONFIG_DIR="$HOME/.gemini/config"
AGY_SKILLS_LINK="$HOME/.gemini/antigravity-cli/skills"
SHARED_SKILLS_DIR="$HOME/.agents/skills"

copy_to_repo "$AGY_CONFIG_DIR/settings.json" "$SCRIPT_DIR/settings.json"
copy_to_repo "$AGY_CONFIG_DIR/keybindings.json" "$SCRIPT_DIR/keybindings.json"
copy_to_repo "$ANTIGRAVITY_SUPPORT_DIR/statusline.sh" "$SCRIPT_DIR/statusline.sh"
copy_to_repo "$ANTIGRAVITY_SUPPORT_DIR/debug_statusline.sh" "$SCRIPT_DIR/debug_statusline.sh"
copy_to_repo "$ANTIGRAVITY_GLOBAL_CONFIG_DIR/skills.json" "$SCRIPT_DIR/skills.json"

if [[ ! -L "$AGY_SKILLS_LINK" || "$(readlink "$AGY_SKILLS_LINK" 2>/dev/null || true)" != "$SHARED_SKILLS_DIR" ]]; then
  log_warn "Agy is not linked to the shared skills directory: $AGY_SKILLS_LINK"
fi

# Never backed up: brain/ (per-session runtime), last_payload.json (ephemeral)

log_info "Antigravity CLI config backed up."

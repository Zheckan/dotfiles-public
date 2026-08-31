#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"

log_section "Antigravity CLI — Install"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ANTIGRAVITY_SUPPORT_DIR="$HOME/.antigravity"
AGY_CONFIG_DIR="$HOME/.gemini/antigravity-cli"
ANTIGRAVITY_GLOBAL_CONFIG_DIR="$HOME/.gemini/config"
AGY_SKILLS_LINK="$HOME/.gemini/antigravity-cli/skills"
SHARED_SKILLS_DIR="$HOME/.agents/skills"

# Install the agy binary if missing
if ! command_exists agy; then
  log_info "Installing Antigravity CLI from antigravity.google..."
  curl -fsSL https://antigravity.google/cli/install.sh | bash
else
  log_info "Antigravity CLI already installed."
fi

# Copy config files
copy_to_system "$SCRIPT_DIR/settings.json" "$AGY_CONFIG_DIR/settings.json"
copy_to_system "$SCRIPT_DIR/keybindings.json" "$AGY_CONFIG_DIR/keybindings.json"
copy_to_system "$SCRIPT_DIR/statusline.sh" "$ANTIGRAVITY_SUPPORT_DIR/statusline.sh"
copy_to_system "$SCRIPT_DIR/debug_statusline.sh" "$ANTIGRAVITY_SUPPORT_DIR/debug_statusline.sh"
copy_to_system "$SCRIPT_DIR/skills.json" "$ANTIGRAVITY_GLOBAL_CONFIG_DIR/skills.json"

# Antigravity 2.0 reads the global skills manifest above. The Agy CLI uses its
# own global skills directory, so point that directory at the shared catalog.
ensure_dir "$(dirname "$AGY_SKILLS_LINK")"
if [[ -L "$AGY_SKILLS_LINK" ]]; then
  ln -sfn "$SHARED_SKILLS_DIR" "$AGY_SKILLS_LINK"
  log_info "Updated Agy shared skills link → $SHARED_SKILLS_DIR"
elif [[ -e "$AGY_SKILLS_LINK" ]]; then
  log_warn "Skipping Agy shared skills link because $AGY_SKILLS_LINK already exists and is not a symlink"
else
  ln -s "$SHARED_SKILLS_DIR" "$AGY_SKILLS_LINK"
  log_info "Linked Agy skills → $SHARED_SKILLS_DIR"
fi

log_manual "Run 'agy' to authenticate with Google Antigravity"

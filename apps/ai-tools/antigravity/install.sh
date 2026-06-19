#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"

log_section "Antigravity CLI — Install"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ANTIGRAVITY_CONFIG_DIR="$HOME/.antigravity"

# Install the agy binary if missing
if ! command_exists agy; then
  log_info "Installing Antigravity CLI from antigravity.google..."
  curl -fsSL https://antigravity.google/cli/install.sh | bash
else
  log_info "Antigravity CLI already installed."
fi

# Copy config files
copy_to_system "$SCRIPT_DIR/settings.json" "$ANTIGRAVITY_CONFIG_DIR/settings.json"
copy_to_system "$SCRIPT_DIR/statusline.sh" "$ANTIGRAVITY_CONFIG_DIR/statusline.sh"
copy_to_system "$SCRIPT_DIR/debug_statusline.sh" "$ANTIGRAVITY_CONFIG_DIR/debug_statusline.sh"

sync_dir_to_system "$SCRIPT_DIR/skills" "$ANTIGRAVITY_CONFIG_DIR/skills"

log_manual "Run 'agy' to authenticate with Google Antigravity"

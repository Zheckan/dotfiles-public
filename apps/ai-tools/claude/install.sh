#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"

log_section "Claude Code — Install"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_CONFIG_DIR="$HOME/.claude"

# Install Claude Code if missing
if command_exists claude; then
  log_info "Claude Code is already installed."
else
  log_info "Installing Claude Code..."
  curl -fsSL https://claude.ai/install.sh | sh
fi

# Config files
copy_to_system "$SCRIPT_DIR/settings.json" "$CLAUDE_CONFIG_DIR/settings.json"
copy_to_system "$SCRIPT_DIR/keybindings.json" "$CLAUDE_CONFIG_DIR/keybindings.json"
copy_to_system "$SCRIPT_DIR/statusline-command.sh" "$CLAUDE_CONFIG_DIR/statusline-command.sh"

# Plugins list
if [[ -f "$SCRIPT_DIR/plugins/installed_plugins.json" ]]; then
  ensure_dir "$CLAUDE_CONFIG_DIR/plugins"
  copy_to_system "$SCRIPT_DIR/plugins/installed_plugins.json" "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
fi

# Restore from dotfiles (rules + custom commands/agents/skills)
# Restore the files managed by this repository.
for dir in rules commands agents skills; do
  if [[ -d "$SCRIPT_DIR/$dir" ]]; then
    sync_dir_to_system "$SCRIPT_DIR/$dir" "$CLAUDE_CONFIG_DIR/$dir"
  fi
done

log_manual "Run 'claude' once to complete setup and authenticate"

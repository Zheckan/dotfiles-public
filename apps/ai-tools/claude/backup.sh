#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"

log_section "Claude Code — Backup"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_CONFIG_DIR="$HOME/.claude"

# Config files
copy_to_repo "$CLAUDE_CONFIG_DIR/settings.json" "$SCRIPT_DIR/settings.json"
copy_to_repo "$CLAUDE_CONFIG_DIR/keybindings.json" "$SCRIPT_DIR/keybindings.json"
copy_to_repo "$CLAUDE_CONFIG_DIR/statusline-command.sh" "$SCRIPT_DIR/statusline-command.sh"

# Plugins list (strip machine-specific installPath and volatile lastUpdated).
# Claude Code rewrites lastUpdated on every plugin update check even when
# nothing changes, which produced a daily no-op backup commit. gitCommitSha
# and version are kept — those move only on a real plugin update.
if [[ -f "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json" ]]; then
  ensure_dir "$SCRIPT_DIR/plugins"
  tmp="$(mktemp)"
  if jq 'walk(if type == "object" then del(.installPath, .lastUpdated) else . end)' \
       "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json" > "$tmp"; then
    mv "$tmp" "$SCRIPT_DIR/plugins/installed_plugins.json"
    log_info "Backed up installed_plugins.json (stripped installPath, lastUpdated)"
  else
    rm -f "$tmp"
    copy_to_repo "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json" "$SCRIPT_DIR/plugins/installed_plugins.json"
    log_warn "jq failed — backed up installed_plugins.json as-is"
  fi
fi

# Rules (only thing ECC plugin can't provide at runtime — must be on disk)
sync_dir_to_repo "$CLAUDE_CONFIG_DIR/rules" "$SCRIPT_DIR/rules"

# Custom commands, agents, and skills
# Plugin provides its own from cache at runtime — anything in these
# folders is custom (plugin never writes to them directly).
sync_dir_to_repo "$CLAUDE_CONFIG_DIR/commands" "$SCRIPT_DIR/commands"
sync_dir_to_repo "$CLAUDE_CONFIG_DIR/agents" "$SCRIPT_DIR/agents"
sync_dir_to_repo "$CLAUDE_CONFIG_DIR/skills" "$SCRIPT_DIR/skills"

log_info "Claude Code config backed up."

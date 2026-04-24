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

# Install ECC plugin (provides commands, agents, skills, hooks at runtime)
if command_exists claude; then
  log_info "Installing Everything Claude Code plugin..."
  if ! claude /plugin marketplace add affaan-m/everything-claude-code 2>/dev/null; then
    log_warn "Failed to add ECC marketplace (auth may be required — run 'claude' first)"
  fi
  if ! claude /plugin install everything-claude-code@everything-claude-code 2>/dev/null; then
    log_warn "Failed to install ECC plugin (auth may be required — run 'claude' first)"
  fi

  # Install ECC rules (only thing the plugin can't provide at runtime)
  # Modules: core + framework-language, database, security, research-apis,
  #          agentic-patterns, devops-infra, document-processing, orchestration
  # Languages: typescript, python, golang, cpp, csharp
  ECC_DIR="$CLAUDE_CONFIG_DIR/plugins/cache/everything-claude-code/everything-claude-code"
  ECC_VERSION=$(ls "$ECC_DIR" 2>/dev/null | sort -V | tail -1)
  if [[ -n "$ECC_VERSION" && -x "$ECC_DIR/$ECC_VERSION/install.sh" ]]; then
    cd "$ECC_DIR/$ECC_VERSION" && npm install --silent 2>/dev/null
    ./install.sh \
      --modules rules-core,agents-core,commands-core,hooks-runtime,platform-configs,workflow-quality,framework-language,database,security,research-apis,agentic-patterns,devops-infra,document-processing,orchestration \
      2>/dev/null
    cd - >/dev/null

    # Remove unwanted language rules (keep: ts, python, golang, cpp, csharp)
    for lang in java kotlin swift perl rust php; do
      rm -rf "$CLAUDE_CONFIG_DIR/rules/$lang"
    done
    # ECC installer dumps commands/agents/skills/hooks/scripts to ~/.claude/
    # but the plugin already provides these at runtime from its cache.
    # Nuke the duplicates — dotfiles restore (below) puts back only custom files.
    rm -rf "$CLAUDE_CONFIG_DIR/commands" "$CLAUDE_CONFIG_DIR/agents"
    rm -rf "$CLAUDE_CONFIG_DIR/skills" "$CLAUDE_CONFIG_DIR/scripts" "$CLAUDE_CONFIG_DIR/mcp-configs"
    rm -f "$CLAUDE_CONFIG_DIR/hooks/hooks.json" "$CLAUDE_CONFIG_DIR/hooks/README.md"
    rm -f "$CLAUDE_CONFIG_DIR/AGENTS.md"
    log_info "ECC rules installed — cleaned runtime duplicates"
  else
    log_warn "ECC plugin cache not found — install rules manually"
  fi
else
  log_manual "Install Claude Code, then re-run this script for ECC setup"
fi

# Restore from dotfiles (rules + custom commands/agents/skills)
# Runs AFTER ECC cleanup so our customizations win
for dir in rules commands agents skills; do
  if [[ -d "$SCRIPT_DIR/$dir" ]]; then
    sync_dir_to_system "$SCRIPT_DIR/$dir" "$CLAUDE_CONFIG_DIR/$dir"
  fi
done

log_manual "Run 'claude' once to complete setup and authenticate"

#!/usr/bin/env bash
# backup.sh — Master backup: copies FROM system INTO repo
# Run: ./backup.sh

source "$(dirname "$0")/_helpers.sh"

# Override set -e for the master backup — individual failures should not
# kill the entire run. Each sub-script still has its own error handling.
set +e

log_section "Dotfiles Backup"

# ── Run sub-backup scripts ─────────────────────────────────────────────

run_backup() {
  local label="$1"
  local script="$2"
  log_section "$label"
  if [[ -x "$script" ]]; then
    "$script" || log_warn "Failed: $label (continuing)"
  else
    log_warn "Script not found or not executable: $script"
  fi
}

run_backup "Apps (Brewfile)"       "$DOTFILES_DIR/apps/backup.sh"
run_backup "Shell"                 "$DOTFILES_DIR/cli/shell/backup.sh"
run_backup "Git"                   "$DOTFILES_DIR/cli/git/backup.sh"
run_backup "Terminal (Ghostty)"    "$DOTFILES_DIR/apps/terminal/ghostty/backup.sh"
run_backup "Node (Globals)"        "$DOTFILES_DIR/languages/node/globals/backup.sh"
run_backup "Python"                "$DOTFILES_DIR/languages/python/backup.sh"
run_backup "Python (Globals)"      "$DOTFILES_DIR/languages/python/globals/backup.sh"
run_backup "Editors — Cursor"      "$DOTFILES_DIR/apps/editors/cursor/backup.sh"
run_backup "Editors — VS Code"     "$DOTFILES_DIR/apps/editors/vscode/backup.sh"
run_backup "Editors — Zed"         "$DOTFILES_DIR/apps/editors/zed/backup.sh"
run_backup "AI Tools — Claude"     "$DOTFILES_DIR/apps/ai-tools/claude/backup.sh"
run_backup "AI Tools — Codex"      "$DOTFILES_DIR/apps/ai-tools/codex/backup.sh"
run_backup "AI Tools — Gemini"     "$DOTFILES_DIR/apps/ai-tools/gemini/backup.sh"
run_backup "AI Tools — OpenCode"   "$DOTFILES_DIR/apps/ai-tools/opencode/backup.sh"
run_backup "SSH"                   "$DOTFILES_DIR/cli/ssh/backup.sh"
run_backup "Misc — GitHub CLI"     "$DOTFILES_DIR/cli/misc/gh/backup.sh"
run_backup "Misc — mise"           "$DOTFILES_DIR/cli/misc/mise/backup.sh"
run_backup "Misc — Conda"          "$DOTFILES_DIR/languages/python/conda/backup.sh"
run_backup "Misc — Yarn"           "$DOTFILES_DIR/languages/node/yarn/backup.sh"
run_backup "Misc — mactop"         "$DOTFILES_DIR/cli/misc/mactop/backup.sh"
run_backup "MultiViewer for F1"   "$DOTFILES_DIR/apps/multiviewer/backup.sh"
run_backup "macOS Defaults"        "$DOTFILES_DIR/macos/backup.sh"
run_backup "History"               "$DOTFILES_DIR/history/backup.sh"

log_section "Backup Complete"
log_info "All dotfiles backed up into $DOTFILES_DIR"

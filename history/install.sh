#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/.." && pwd)/_helpers.sh"

log_section "Shell History — Install"

HISTORY_FILE="$DOTFILES_DIR/history/.zsh_history"

if [[ -f "$HISTORY_FILE" ]]; then
  log_warn "This will overwrite your current history with the backed-up version"
  cp "$DOTFILES_DIR/history/.zsh_history" ~/.zsh_history
  log_info "Shell history restored from backup."
else
  log_warn "No .zsh_history file found in repo — skipping."
fi

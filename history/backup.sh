#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/.." && pwd)/_helpers.sh"

log_section "Shell History — Backup"

if [[ -f "$HOME/.zsh_history" ]]; then
  tail -n 10000 ~/.zsh_history > "$DOTFILES_DIR/history/.zsh_history"
  LINES_BACKED=$(wc -l < "$DOTFILES_DIR/history/.zsh_history")
  log_info "Backed up $LINES_BACKED lines of shell history."
else
  log_warn "No ~/.zsh_history found — skipping."
fi

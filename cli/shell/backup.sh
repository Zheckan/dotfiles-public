#!/usr/bin/env bash
# cli/shell/backup.sh — Back up Zsh config and theme into repo

source "$(cd "$(dirname "$0")/../.." && pwd)/_helpers.sh"

SHELL_DIR="$DOTFILES_DIR/cli/shell"

# ── Shell dotfiles ─────────────────────────────────────────────────────

copy_to_repo "$HOME/.zshrc" "$SHELL_DIR/.zshrc"
copy_to_repo "$HOME/.zshenv" "$SHELL_DIR/.zshenv"
copy_to_repo "$HOME/.zprofile" "$SHELL_DIR/.zprofile"

# ── Theme ──────────────────────────────────────────────────────────────

ensure_dir "$SHELL_DIR/themes"
copy_to_repo "$HOME/.oh-my-zsh/custom/themes/theunraveler.zsh-theme" "$SHELL_DIR/themes/theunraveler.zsh-theme"

log_info "Shell configuration backed up."

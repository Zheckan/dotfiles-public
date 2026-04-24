#!/usr/bin/env bash
# cli/git/backup.sh — Back up Git configuration into repo

source "$(cd "$(dirname "$0")/../.." && pwd)/_helpers.sh"

GIT_DIR="$DOTFILES_DIR/cli/git"

copy_to_repo "$HOME/.gitconfig" "$GIT_DIR/.gitconfig"
copy_to_repo "$HOME/.gitignore_global" "$GIT_DIR/.gitignore_global"

log_info "Git configuration backed up."

#!/usr/bin/env bash
# cli/git/install.sh — Install Git configuration files

source "$(cd "$(dirname "$0")/../.." && pwd)/_helpers.sh"

GIT_DIR="$DOTFILES_DIR/cli/git"

copy_to_system "$GIT_DIR/.gitconfig" "$HOME/.gitconfig"
copy_to_system "$GIT_DIR/.gitignore_global" "$HOME/.gitignore_global"

log_manual "Create ~/.gitconfig_work if needed (see cli/git/templates/README.md)"

log_info "Git configuration installed."

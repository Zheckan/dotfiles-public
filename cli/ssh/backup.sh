#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../.." && pwd)/_helpers.sh"

log_section "SSH Backup"

# Back up SSH config only — NEVER copy private keys
copy_to_repo "$HOME/.ssh/config" "$DOTFILES_DIR/cli/ssh/config"

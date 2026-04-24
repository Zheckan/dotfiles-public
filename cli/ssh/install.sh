#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../.." && pwd)/_helpers.sh"

log_section "SSH"

# Ensure ~/.ssh exists with correct permissions
ensure_dir ~/.ssh
chmod 700 ~/.ssh

# Copy SSH config from repo to system
copy_to_system "$DOTFILES_DIR/cli/ssh/config" "$HOME/.ssh/config"

# Generate SSH key if one doesn't already exist
if [[ ! -f ~/.ssh/id_ed25519 ]]; then
  log_info "Generating new ed25519 SSH key..."
  ssh-keygen -t ed25519 -C "$(git config user.email)" -f ~/.ssh/id_ed25519 -N ""
  log_manual "Add your SSH key to GitHub: https://github.com/settings/keys"
  log_manual "Run: cat ~/.ssh/id_ed25519.pub | pbcopy"
else
  log_info "SSH key already exists"
fi

# Print manual steps if run standalone
if [[ ${#MANUAL_STEPS[@]} -gt 0 ]]; then
  print_manual_steps
fi

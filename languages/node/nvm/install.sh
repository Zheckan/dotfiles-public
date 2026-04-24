#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"

log_section "nvm — Install"

NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

if [[ -d "$NVM_DIR" ]]; then
  log_info "nvm is already installed at $NVM_DIR."
else
  log_info "Installing nvm..."
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
  log_info "nvm installed successfully."
fi

log_info "Restart your shell, then run: nvm install --lts"

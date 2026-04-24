#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"

log_section "pnpm — Install"

if command_exists pnpm; then
  log_info "pnpm is already installed."
else
  log_info "Installing pnpm..."
  curl -fsSL https://get.pnpm.io/install.sh | sh -
  log_info "pnpm installed successfully."
fi

if command_exists pnpm; then
  log_info "pnpm version: $(pnpm --version)"
fi

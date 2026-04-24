#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"

log_section "Bun — Install"

if command_exists bun; then
  log_info "Bun is already installed."
else
  log_info "Installing Bun via Homebrew..."
  brew install bun
fi

if command_exists bun; then
  log_info "Bun version: $(bun --version)"
fi

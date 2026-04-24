#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/.." && pwd)/_helpers.sh"

log_section "macOS Defaults"

log_warn "This will change macOS system preferences. Review macos/defaults.sh first."

# Apply macOS defaults
source "$DOTFILES_DIR/macos/defaults.sh"

log_info "macOS defaults applied. Some changes require logout/restart."

#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/.." && pwd)/_helpers.sh"

log_section "Fonts"

log_info "Fonts are installed via Homebrew cask entries in the Brewfile."
log_info "Run apps/install.sh (or the root install.sh) to install fonts."
log_info "Fonts included: font-geist-mono, font-jetbrains-mono, etc. (whatever is in Brewfile)"

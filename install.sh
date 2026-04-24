#!/usr/bin/env bash
# install.sh — Master installer: copies FROM repo TO system
# Run: ./install.sh

source "$(dirname "$0")/_helpers.sh"

log_section "Dotfiles Installer"

# ── Pre-flight checks ─────────────────────────────────────────────────

# 1. Require macOS
if [[ "$(uname -s)" != "Darwin" ]]; then
  log_error "This dotfiles repo is designed for macOS only."
  exit 1
fi
log_info "Running on macOS $(sw_vers -productVersion)"

# 2. Xcode Command Line Tools
if ! xcode-select -p &>/dev/null; then
  log_info "Installing Xcode Command Line Tools..."
  xcode-select --install
  log_info "Waiting for Xcode CLT installation to complete..."
  until xcode-select -p &>/dev/null; do
    sleep 5
  done
  log_info "Xcode Command Line Tools installed."
else
  log_info "Xcode Command Line Tools already installed."
fi

# 3. Homebrew
if ! command_exists brew; then
  log_info "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Ensure brew is on PATH for the rest of this session
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
  log_info "Homebrew installed."
else
  log_info "Homebrew already installed."
fi

# ── Run sub-installers in order ────────────────────────────────────────

log_section "Apps (Homebrew Bundle)"
"$DOTFILES_DIR/apps/install.sh"

log_section "Shell (Zsh + Oh My Zsh)"
"$DOTFILES_DIR/cli/shell/install.sh"

log_section "Git"
"$DOTFILES_DIR/cli/git/install.sh"

log_section "Terminal"
"$DOTFILES_DIR/apps/terminal/install.sh"

log_section "Node"
"$DOTFILES_DIR/languages/node/install.sh"

log_section "Python"
"$DOTFILES_DIR/languages/python/install.sh"

log_section "Editors"
"$DOTFILES_DIR/apps/editors/install.sh"

log_section "AI Tools"
"$DOTFILES_DIR/apps/ai-tools/install.sh"

log_section "SSH"
"$DOTFILES_DIR/cli/ssh/install.sh"

log_section "Fonts"
"$DOTFILES_DIR/fonts/install.sh"

log_section "macOS Defaults"
"$DOTFILES_DIR/macos/install.sh"

log_section "Misc"
"$DOTFILES_DIR/cli/misc/install.sh"

log_section "History"
"$DOTFILES_DIR/history/install.sh"

log_section "Auto-Backup"
"$DOTFILES_DIR/auto-backup/install.sh"

# ── Summary ────────────────────────────────────────────────────────────

log_section "Installation Complete"
print_manual_steps

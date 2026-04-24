#!/usr/bin/env bash
# apps/install.sh — Install Homebrew packages from Brewfile

source "$(cd "$(dirname "$0")/.." && pwd)/_helpers.sh"

log_section "Apps (Brewfile)"

BREWFILE="$DOTFILES_DIR/apps/Brewfile"

if [[ -f "$BREWFILE" ]]; then
  log_info "Installing packages from Brewfile..."
  brew bundle --file="$BREWFILE"
  log_info "Homebrew bundle install complete."
else
  log_warn "No Brewfile found at $BREWFILE — skipping."
fi

# ── App-specific config restore ────────────────────────────────────
"$DOTFILES_DIR/apps/multiviewer/install.sh"

# Manual steps after install
log_manual "Sign into Mac App Store apps (Goodnotes, Xcode, etc.)"
log_manual "Sign into Microsoft Office (Word, Excel, PowerPoint)"
log_manual "Sign into communication apps (Slack, Discord, Telegram, WhatsApp)"
log_manual "Sign into Spotify, Notion, Obsidian, Figma, Linear"
log_manual "Activate CrossOver license"
log_manual "Install FPV LOGIC manually (not available via Homebrew)"
log_manual "Configure Logi Options+ for your peripherals"
log_manual "Review Brewfile and remove unwanted apps before running on a new machine"

#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/.." && pwd)/_helpers.sh"

log_section "Auto-Backup LaunchAgent — Install"

DOTFILES_REPO_DIR="${DOTFILES_REPO_DIR:-$DOTFILES_DIR}"
DOTFILES_LOG_DIR="${DOTFILES_LOG_DIR:-$HOME/Library/Logs/dotfiles}"
DOTFILES_AUTOBACKUP_LOCKFILE="${DOTFILES_AUTOBACKUP_LOCKFILE:-/tmp/dotfiles-autocommit.lock}"
PLIST_DEST="$HOME/Library/LaunchAgents/com.dotfiles.autocommit.plist"

xml_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  value="${value//\"/&quot;}"
  printf '%s' "$value"
}

ensure_dir "$HOME/Library/LaunchAgents"
ensure_dir "$DOTFILES_LOG_DIR"

DOTFILES_GITHUB_REPO="${DOTFILES_GITHUB_REPO:-}"

cat > "$PLIST_DEST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.dotfiles.autocommit</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>-lc</string>
    <string>exec "\$DOTFILES_REPO_DIR/auto-backup/run-backup.sh"</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>DOTFILES_REPO_DIR</key>
    <string>$(xml_escape "$DOTFILES_REPO_DIR")</string>
    <key>DOTFILES_GITHUB_REPO</key>
    <string>$(xml_escape "$DOTFILES_GITHUB_REPO")</string>
    <key>DOTFILES_LOG_DIR</key>
    <string>$(xml_escape "$DOTFILES_LOG_DIR")</string>
    <key>DOTFILES_AUTOBACKUP_LOCKFILE</key>
    <string>$(xml_escape "$DOTFILES_AUTOBACKUP_LOCKFILE")</string>
  </dict>
  <key>StartInterval</key>
  <integer>172800</integer>
  <key>StandardOutPath</key>
  <string>$(xml_escape "$DOTFILES_LOG_DIR")/dotfiles-autocommit.log</string>
  <key>StandardErrorPath</key>
  <string>$(xml_escape "$DOTFILES_LOG_DIR")/dotfiles-autocommit.log</string>
</dict>
</plist>
PLIST

launchctl unload "$PLIST_DEST" 2>/dev/null || true
launchctl load "$PLIST_DEST"

log_info "Auto-backup LaunchAgent installed (runs every 2 days)"
log_info "LaunchAgent plist written to $PLIST_DEST"
log_info ""
log_info "Alternative: run ./install-shortcut.sh for an Apple Shortcuts-based approach."

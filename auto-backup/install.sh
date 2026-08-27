#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/.." && pwd)/_helpers.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

log_section "Auto-Backup LaunchAgent — Install"

DOTFILES_REPO_DIR="${DOTFILES_REPO_DIR:-$DOTFILES_DIR}"
DOTFILES_LOG_DIR="${DOTFILES_LOG_DIR:-$HOME/Library/Logs/dotfiles}"
DOTFILES_AUTOBACKUP_LOCKFILE="${DOTFILES_AUTOBACKUP_LOCKFILE:-/tmp/dotfiles-autocommit.lock}"
PLIST_DEST="$HOME/Library/LaunchAgents/com.dotfiles.autocommit.plist"
CONFIG_FILE="${DOTFILES_AUTOBACKUP_CONFIG_FILE:-$SCRIPT_DIR/config.local.toml}"

configure_if_needed() {
  local reason="$1"

  log_warn "$reason"
  if [[ -t 0 && -t 1 ]]; then
    "$SCRIPT_DIR/configure.sh"
  else
    log_error "Run $SCRIPT_DIR/configure.sh in an interactive terminal, then reinstall."
    exit 1
  fi
}

validate_machine_config() {
  local output key value reviewers="" models=""
  local api_key="${OPENCODE_GO_API_KEY:-}"
  local env_file="${DOTFILES_OPENCODE_GO_ENV_FILE:-$SCRIPT_DIR/.env}"

  output="$(python3 "$SCRIPT_DIR/config.py" "$CONFIG_FILE")" || return 1
  while IFS=$'\t' read -r key value; do
    case "$key" in
      DOTFILES_REVIEWERS) reviewers="$value" ;;
      DOTFILES_REVIEW_OPENCODE_GO_API_MODELS) models="$value" ;;
    esac
  done <<< "$output"

  if [[ -e "$env_file" ]]; then
    if [[ "$env_file" == "$SCRIPT_DIR/.env" ]] &&
      git -C "$DOTFILES_REPO_DIR" ls-files --error-unmatch -- "auto-backup/.env" &>/dev/null; then
      log_error "auto-backup/.env contains a secret and must not be tracked."
      return 1
    fi
    python3 "$SCRIPT_DIR/opencode_go.py" read-key "$env_file" > /dev/null ||
      return 1
  fi

  case ",$reviewers," in
    *,opencode-go-api,*)
      if [[ -z "$api_key" ]]; then
        api_key="$(python3 "$SCRIPT_DIR/opencode_go.py" read-key "$env_file")" ||
          return 1
      fi
      key="${models%%,*}"
      if ! OPENCODE_GO_API_KEY="$api_key" \
        python3 "$SCRIPT_DIR/opencode_go.py" validate "$key"; then
        log_error "OpenCode Go API key validation failed."
        return 1
      fi
      log_info "OpenCode Go API key is valid"
      ;;
  esac
}

if [[ "${DOTFILES_AUTOBACKUP_INSTALL_SOURCE_ONLY:-false}" == "true" ]]; then
  return 0 2>/dev/null || exit 0
fi

[[ -f "$CONFIG_FILE" ]] ||
  configure_if_needed "Required auto-backup configuration is missing."
if ! command_exists python3; then
  log_error "python3 is required to validate auto-backup/config.local.toml."
  exit 1
fi
if ! validate_machine_config; then
  configure_if_needed "Auto-backup configuration or credentials are invalid."
  if ! validate_machine_config; then
    log_error "Auto-backup configuration or credentials are still invalid."
    exit 1
  fi
fi

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

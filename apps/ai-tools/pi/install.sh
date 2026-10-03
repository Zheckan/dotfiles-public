#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"

log_section "Pi — Install"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PI_CONFIG_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
export PATH="$PI_CONFIG_DIR/bin:$HOME/.local/bin:$PATH"

if command_exists pi; then
  log_info "Pi is already installed."
else
  require_command curl
  installer="$(mktemp -d)"
  trap 'rm -rf "$installer"' EXIT
  log_info "Installing Pi from pi.dev..."
  curl -fsSL https://pi.dev/install.sh -o "$installer/install.sh"
  # Keep stdout non-terminal so the installer does not launch an interactive
  # Pi session before this script has restored configuration.
  if ! sh "$installer/install.sh" > "$installer/install.log" 2>&1; then
    while IFS= read -r line; do printf '%s\n' "$line"; done < "$installer/install.log"
    log_error "Pi installer failed; config was not restored."
    exit 1
  fi
  require_command pi
  log_info "Pi installed."
fi

if [[ -d "$SCRIPT_DIR/config" ]]; then
  require_command rsync
  ensure_dir "$PI_CONFIG_DIR/.dotfiles-restore-backups"
  restore_backup="$(mktemp -d "$PI_CONFIG_DIR/.dotfiles-restore-backups/restore.XXXXXX")"
  # Additive restore: keep local resources, credentials, sessions, dependency
  # trees, and runtime. Changed files are saved before replacement.
  rsync -ac --backup --backup-dir="$restore_backup" "$SCRIPT_DIR/config/" "$PI_CONFIG_DIR/"
  log_info "Restored Pi config; replaced files saved under $restore_backup"
  if grep -rq 'REDACTED_SET_THIS_SECRET_ON_RESTORE' "$SCRIPT_DIR/config"; then
    log_manual "Replace REDACTED_SET_THIS_SECRET_ON_RESTORE in Pi config: model API keys, MCP env/header/OAuth secrets, URLs, or credential arguments. Affected files:"
    grep -rl 'REDACTED_SET_THIS_SECRET_ON_RESTORE' "$SCRIPT_DIR/config"
  fi
  if [[ -f "$SCRIPT_DIR/config/settings.json" ]]; then
    log_manual "Run 'pi update --extensions' to reinstall packages declared in settings.json."
  fi
  for resource in extensions skills; do
    if [[ -d "$SCRIPT_DIR/config/$resource" ]] && find "$SCRIPT_DIR/config/$resource" -name package.json -print -quit | grep -q .; then
      log_manual "Install runtime dependencies for your local Pi extensions/skills using their package.json and lockfiles."
      break
    fi
  done
fi

log_manual "Run 'pi' and '/login' to authenticate; use '/mcp login <server>' for MCP OAuth servers and approve projects again."

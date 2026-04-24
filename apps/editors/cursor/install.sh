#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"

log_section "Cursor — Install"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CURSOR_USER_DIR="$HOME/Library/Application Support/Cursor/User"
CURSOR_MCP_DIR="$HOME/.cursor"

# Default-profile config files
copy_to_system "$SCRIPT_DIR/settings.json" "$CURSOR_USER_DIR/settings.json"
copy_to_system "$SCRIPT_DIR/keybindings.json" "$CURSOR_USER_DIR/keybindings.json"

# Skip copying mcp.json if the tracked file is empty (would clobber real config)
if [[ -s "$SCRIPT_DIR/mcp.json" ]]; then
  copy_to_system "$SCRIPT_DIR/mcp.json" "$CURSOR_MCP_DIR/mcp.json"
elif [[ -f "$SCRIPT_DIR/mcp.json" ]]; then
  log_warn "Skipping empty Cursor mcp.json to avoid overwriting $CURSOR_MCP_DIR/mcp.json"
fi

copy_to_system "$SCRIPT_DIR/argv.json" "$CURSOR_MCP_DIR/argv.json"

# Default-profile snippets
sync_dir_to_system "$SCRIPT_DIR/snippets" "$CURSOR_USER_DIR/snippets"

# Restore profiles non-destructively (no --delete). The backup intentionally
# omits runtime state (globalStorage/, workspaceStorage/, History/, ...); using
# rsync --delete here would wipe those on any non-fresh machine.
if [[ -d "$SCRIPT_DIR/profiles" ]]; then
  ensure_dir "$CURSOR_USER_DIR/profiles"
  rsync -a --exclude='.DS_Store' "$SCRIPT_DIR/profiles/" "$CURSOR_USER_DIR/profiles/"
  # Rehydrate ${HOME} placeholders (see backup sanitization) back to real path.
  find "$CURSOR_USER_DIR/profiles" -type f -name 'extensions.json' -print0 \
    | xargs -0 sed -i '' "s#\${HOME}#${HOME}#g"
  log_info "Restored profiles → $CURSOR_USER_DIR/profiles"
fi

# Profile metadata (userDataProfiles, profileAssociations).
# Contains device-specific telemetry IDs — restore manually only on a fresh
# machine, and review before copying.
if [[ -f "$SCRIPT_DIR/globalStorage/storage.json" ]]; then
  log_manual "Cursor profile metadata available at apps/editors/cursor/globalStorage/storage.json — inspect before restoring to $CURSOR_USER_DIR/globalStorage/storage.json"
fi

# Install extensions
if command_exists cursor; then
  if [[ -f "$SCRIPT_DIR/extensions.txt" ]]; then
    log_info "Installing Cursor extensions..."
    while IFS= read -r ext || [[ -n "$ext" ]]; do
      [[ -z "$ext" || "$ext" == \#* ]] && continue
      cursor --install-extension "$ext" || log_warn "Failed to install extension: $ext"
    done < "$SCRIPT_DIR/extensions.txt"
    log_info "Cursor extensions installed."
  else
    log_warn "extensions.txt not found — skipping extension install."
  fi
else
  log_manual "Cursor CLI not found. Install extensions manually from extensions.txt."
fi

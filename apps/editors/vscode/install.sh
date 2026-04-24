#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"

log_section "VS Code — Install"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VSCODE_USER_DIR="$HOME/Library/Application Support/Code/User"
VSCODE_CLI_DIR="$HOME/.vscode"

# Default-profile config files
copy_to_system "$SCRIPT_DIR/settings.json" "$VSCODE_USER_DIR/settings.json"
copy_to_system "$SCRIPT_DIR/keybindings.json" "$VSCODE_USER_DIR/keybindings.json"

# Skip copying mcp.json if the tracked file is empty (would clobber real config)
if [[ -s "$SCRIPT_DIR/mcp.json" ]]; then
  copy_to_system "$SCRIPT_DIR/mcp.json" "$VSCODE_USER_DIR/mcp.json"
elif [[ -f "$SCRIPT_DIR/mcp.json" ]]; then
  log_warn "Skipping empty VS Code mcp.json to avoid overwriting $VSCODE_USER_DIR/mcp.json"
fi

copy_to_system "$SCRIPT_DIR/argv.json" "$VSCODE_CLI_DIR/argv.json"

# Default-profile snippets
sync_dir_to_system "$SCRIPT_DIR/snippets" "$VSCODE_USER_DIR/snippets"

# Restore profiles non-destructively (no --delete). The backup intentionally
# omits runtime state (globalStorage/, workspaceStorage/, History/, ...); using
# rsync --delete here would wipe those on any non-fresh machine.
if [[ -d "$SCRIPT_DIR/profiles" ]]; then
  ensure_dir "$VSCODE_USER_DIR/profiles"
  rsync -a --exclude='.DS_Store' "$SCRIPT_DIR/profiles/" "$VSCODE_USER_DIR/profiles/"
  # Rehydrate ${HOME} placeholders (see backup sanitization) back to real path.
  find "$VSCODE_USER_DIR/profiles" -type f -name 'extensions.json' -print0 \
    | xargs -0 sed -i '' "s#\${HOME}#${HOME}#g"
  log_info "Restored profiles → $VSCODE_USER_DIR/profiles"
fi

# Profile metadata (userDataProfiles, profileAssociations).
# Contains device-specific telemetry IDs — restore manually only on a fresh
# machine, and review before copying.
if [[ -f "$SCRIPT_DIR/globalStorage/storage.json" ]]; then
  log_manual "VS Code profile metadata available at apps/editors/vscode/globalStorage/storage.json — inspect before restoring to $VSCODE_USER_DIR/globalStorage/storage.json"
fi

# Install extensions
if command_exists code; then
  if [[ -f "$SCRIPT_DIR/extensions.txt" ]]; then
    log_info "Installing VS Code extensions..."
    while IFS= read -r ext || [[ -n "$ext" ]]; do
      [[ -z "$ext" || "$ext" == \#* ]] && continue
      code --install-extension "$ext" || log_warn "Failed to install extension: $ext"
    done < "$SCRIPT_DIR/extensions.txt"
    log_info "VS Code extensions installed."
  else
    log_manual "VS Code CLI ('code') not found. Install extensions manually from extensions.txt."
  fi
else
  log_manual "VS Code CLI ('code') not found. Install extensions manually from extensions.txt."
fi

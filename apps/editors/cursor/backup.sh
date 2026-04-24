#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"

log_section "Cursor — Backup"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CURSOR_USER_DIR="$HOME/Library/Application Support/Cursor/User"
CURSOR_MCP_DIR="$HOME/.cursor"

# Default-profile config files
copy_to_repo "$CURSOR_USER_DIR/settings.json" "$SCRIPT_DIR/settings.json"
copy_to_repo "$CURSOR_USER_DIR/keybindings.json" "$SCRIPT_DIR/keybindings.json"
copy_to_repo "$CURSOR_MCP_DIR/mcp.json" "$SCRIPT_DIR/mcp.json"

# argv.json — strip crash-reporter-id (per-device identifier)
if [[ -f "$CURSOR_MCP_DIR/argv.json" ]] && command_exists python3; then
  python3 - "$CURSOR_MCP_DIR/argv.json" "$SCRIPT_DIR/argv.json" <<'PY'
import json, re, sys
src, dst = sys.argv[1], sys.argv[2]
# argv.json has // comments — strip for parsing, then round-trip as plain JSON
raw = open(src).read()
stripped = re.sub(r"(?m)^\s*//.*$", "", raw)
data = json.loads(stripped)
data.pop("crash-reporter-id", None)
with open(dst, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
  log_info "Backed up sanitized argv.json → $SCRIPT_DIR/argv.json"
elif [[ -f "$CURSOR_MCP_DIR/argv.json" ]]; then
  log_warn "python3 not found — skipping argv.json backup to avoid committing crash-reporter-id"
fi

# Default-profile snippets
sync_dir_to_repo "$CURSOR_USER_DIR/snippets" "$SCRIPT_DIR/snippets"

# All user profiles (per-profile extensions/settings/snippets/keybindings).
# Exclude transient runtime state: SQLite DBs, per-extension state, workspace
# caches. Those are device-local and would bloat the repo on every backup.
if [[ -d "$CURSOR_USER_DIR/profiles" ]]; then
  ensure_dir "$SCRIPT_DIR/profiles"
  rsync -a --delete \
    --exclude='.DS_Store' \
    --exclude='globalStorage/' \
    --exclude='workspaceStorage/' \
    --exclude='History/' \
    --exclude='logs/' \
    --exclude='CachedData/' \
    --exclude='Backups/' \
    "$CURSOR_USER_DIR/profiles/" "$SCRIPT_DIR/profiles/"
  # Sanitize absolute home paths in per-profile extensions.json for portability.
  find "$SCRIPT_DIR/profiles" -type f -name 'extensions.json' -print0 \
    | xargs -0 sed -i '' "s#${HOME}#\${HOME}#g"
  log_info "Synced $CURSOR_USER_DIR/profiles → $SCRIPT_DIR/profiles (excluding runtime state; home path sanitized)"
else
  log_warn "Source directory not found: $CURSOR_USER_DIR/profiles (skipping)"
fi

# Profile metadata — strip workspace path associations (leak username + project tree)
ensure_dir "$SCRIPT_DIR/globalStorage"
STORAGE_SRC="$CURSOR_USER_DIR/globalStorage/storage.json"
STORAGE_DST="$SCRIPT_DIR/globalStorage/storage.json"
if [[ -f "$STORAGE_SRC" ]] && command_exists python3; then
  python3 - "$STORAGE_SRC" "$STORAGE_DST" <<'PY'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    data = json.load(f)
# Whitelist: only keep fields useful for reconstructing profile identity on a
# fresh machine. Drop workspace paths, recent files, backup lists, open windows,
# and anything else that leaks local filesystem state.
KEEP = {"userDataProfiles", "userDataProfilesMigration", "profileAssociationsMigration"}
sanitized = {k: data[k] for k in KEEP if k in data}
with open(dst, "w") as f:
    json.dump(sanitized, f, indent=2)
    f.write("\n")
PY
  log_info "Backed up sanitized Cursor profile metadata → $STORAGE_DST"
elif [[ -f "$STORAGE_SRC" ]]; then
  log_warn "python3 not found — skipping storage.json backup to avoid committing workspace paths"
fi

# Export extensions list (default profile)
if command_exists cursor; then
  log_info "Exporting Cursor extensions list..."
  cursor --list-extensions > "$SCRIPT_DIR/extensions.txt"
  log_info "Extensions list saved to extensions.txt"
else
  log_warn "Cursor CLI not found — skipping extensions export."
fi

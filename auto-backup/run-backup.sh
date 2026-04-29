#!/usr/bin/env bash
# Launcher for auto-commit.sh — ensures the latest version always runs.
#
# Fetches latest from origin, updates auto-backup/ scripts from main,
# then exec's auto-commit.sh so the newest code is always in memory.
# auto-commit.sh handles its own rebase on the device branch.
#
# Usage: same flags as auto-commit.sh
#   run-backup.sh --main-pc
#   run-backup.sh --pr-only
#   run-backup.sh --test
#
# LaunchAgent and Apple Shortcuts should call this instead of auto-commit.sh directly.

# Load Homebrew and user PATH (for non-interactive environments)
eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null)" || true
export PATH="$HOME/.nvm/versions/node/$(ls "$HOME/.nvm/versions/node/" 2>/dev/null | tail -1)/bin:$PATH" 2>/dev/null || true
export PATH="/usr/local/bin:$HOME/.local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_REPO_DIR="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/.." && pwd))"
DOTFILES_REPO_DIR="${DOTFILES_REPO_DIR:-$DEFAULT_REPO_DIR}"
DOTFILES_LOG_DIR="${DOTFILES_LOG_DIR:-$HOME/Library/Logs/dotfiles}"
DOTFILES_AUTOBACKUP_LOCKFILE="${DOTFILES_AUTOBACKUP_LOCKFILE:-/tmp/dotfiles-autocommit.lock}"
export DOTFILES_REPO_DIR DOTFILES_LOG_DIR DOTFILES_AUTOBACKUP_LOCKFILE

cd "$DOTFILES_REPO_DIR" || exit 1

# Early lock check — prevent concurrent git operations.
# auto-commit.sh owns the lock lifecycle; we just bail out early here.
LOCKFILE="$DOTFILES_AUTOBACKUP_LOCKFILE"
if [[ -f "$LOCKFILE" ]]; then
  LOCK_PID=$(cat "$LOCKFILE" 2>/dev/null)
  if kill -0 "$LOCK_PID" 2>/dev/null; then
    echo "run-backup: another instance running (PID $LOCK_PID), skipping" >&2
    exit 0
  fi
fi

LOG_DIR="$DOTFILES_LOG_DIR"
mkdir -p "$LOG_DIR" 2>/dev/null || true
LOG_FILE="$LOG_DIR/dotfiles-autocommit.log"
SCRIPT="$DOTFILES_REPO_DIR/auto-backup/auto-commit.sh"

if [[ -t 0 && -t 1 ]]; then
  # Interactive terminal — run everything in foreground
  git fetch origin > /dev/null 2>&1
  git checkout origin/main -- auto-backup/ 2>/dev/null || true
  exec "$SCRIPT" "$@"
else
  # Non-interactive (Apple Shortcuts, LaunchAgent) — background ALL work
  # (including git fetch) so Shortcuts returns immediately.
  # Avoid nohup — it interferes with reviewer stdout capture.
  (
    git fetch origin || echo "WARN: git fetch origin failed" >&2
    git checkout origin/main -- auto-backup/ || echo "WARN: git checkout origin/main -- auto-backup/ failed" >&2
    "$SCRIPT" "$@"
  ) </dev/null >>"$LOG_FILE" 2>&1 &
  disown 2>/dev/null || true
fi

#!/usr/bin/env bash
# Launcher for auto-commit.sh — ensures the latest version always runs.
#
# Fetches latest from origin, updates auto-backup/ scripts from main when safe,
# then exec's auto-commit.sh so the newest code is usually in memory.
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
NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  export NVM_DIR
  # shellcheck source=/dev/null
  source "$NVM_DIR/nvm.sh" --no-use
  nvm use --silent default > /dev/null 2>&1 || true
fi
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

worktree_has_local_changes() {
  ! git diff --quiet ||
    ! git diff --cached --quiet ||
    [[ -n "$(git ls-files --others --exclude-standard)" ]]
}

refresh_auto_backup_scripts() {
  if ! git fetch origin > /dev/null 2>&1; then
    echo "WARN: git fetch origin failed" >&2
  fi

  if worktree_has_local_changes; then
    echo "run-backup: local changes detected; skipping script refresh before auto-commit can stash them" >&2
    return 0
  fi

  if ! git checkout origin/main -- auto-backup/ > /dev/null 2>&1; then
    echo "WARN: git checkout origin/main -- auto-backup/ failed; continuing with local scripts" >&2
  fi
}

if [[ -t 0 && -t 1 ]]; then
  # Interactive terminal — run everything in foreground
  refresh_auto_backup_scripts
  exec "$SCRIPT" "$@"
else
  # Non-interactive (Apple Shortcuts, LaunchAgent) — background ALL work
  # (including git fetch) so Shortcuts returns immediately.
  # Avoid nohup — it interferes with reviewer stdout capture.
  (
    refresh_auto_backup_scripts
    "$SCRIPT" "$@"
  ) </dev/null >>"$LOG_FILE" 2>&1 &
  disown 2>/dev/null || true
fi

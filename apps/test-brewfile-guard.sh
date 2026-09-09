#!/usr/bin/env bash
# apps/test-brewfile-guard.sh — Guards the Brewfile section-wipeout protection.
#
# This test exists because a node install that shadowed nvm's npm on PATH made
# `brew bundle dump` emit zero npm entries, and the backup committed the
# deletion of all 11 global npm packages from apps/Brewfile.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export DOTFILES_APPS_BACKUP_SOURCE_ONLY=true
# shellcheck source=/dev/null
source "$SCRIPT_DIR/backup.sh"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

failures=0

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    printf '  ok - %s\n' "$name"
  else
    printf '  FAIL - %s\n    expected: %s\n    actual:   %s\n' "$name" "$expected" "$actual" >&2
    failures=$((failures + 1))
  fi
}

# Run the guard over a prev/new pair and return the resulting Brewfile contents.
run_guard() {
  local prev_content="$1" new_content="$2"
  local prev="$WORK_DIR/prev" new="$WORK_DIR/new"

  printf '%s' "$prev_content" > "$prev"
  printf '%s' "$new_content" > "$new"
  restore_wiped_brewfile_sections "$prev" "$new" > /dev/null 2>&1
  cat "$new"
}

printf 'restore_wiped_brewfile_sections\n'

check "restores a wiped npm section" \
  'brew "git"
cask "zed"
npm "eslint"
npm "yarn"' \
  "$(run_guard 'brew "git"
cask "zed"
npm "eslint"
npm "yarn"
' 'brew "git"
cask "zed"
')"

check "leaves a shrunken section alone" \
  'npm "eslint"' \
  "$(run_guard 'npm "eslint"
npm "yarn"
' 'npm "eslint"
')"

check "no-op when the section was already empty" \
  'brew "git"' \
  "$(run_guard 'brew "git"
' 'brew "git"
')"

check "restores every wiped section" \
  'brew "git"
vscode "a.b"
npm "yarn"' \
  "$(run_guard 'brew "git"
vscode "a.b"
npm "yarn"
' 'brew "git"
')"

check "tolerates a missing previous Brewfile (first run)" \
  'brew "git"' \
  "$(printf 'brew "git"\n' > "$WORK_DIR/new"
     restore_wiped_brewfile_sections "$WORK_DIR/does-not-exist" "$WORK_DIR/new" > /dev/null 2>&1
     cat "$WORK_DIR/new")"

if (( failures > 0 )); then
  printf '\n%d Brewfile guard test(s) failed\n' "$failures" >&2
  exit 1
fi

printf 'PASS: Brewfile section-wipeout guard\n'

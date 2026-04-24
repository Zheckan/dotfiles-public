#!/usr/bin/env bash
# _helpers.sh — Shared utilities for dotfiles scripts
# Source this file at the top of every script:
#   source "$(dirname "$0")/../_helpers.sh"  (from a subfolder)
#   source "$(dirname "$0")/_helpers.sh"     (from root)

set -euo pipefail

# ── Repo root detection ──────────────────────────────────────────────
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# If sourced from a subfolder, walk up to find _helpers.sh location
# Since _helpers.sh lives at repo root, DOTFILES_DIR is correct as-is.

# ── Manual steps collector ───────────────────────────────────────────
MANUAL_STEPS=()

# ── Colors ───────────────────────────────────────────────────────────
_RED='\033[0;31m'
_GREEN='\033[0;32m'
_YELLOW='\033[0;33m'
_BLUE='\033[0;34m'
_MAGENTA='\033[0;35m'
_RESET='\033[0m'

# ── Logging ──────────────────────────────────────────────────────────
log_info() {
  printf "${_GREEN}[INFO]${_RESET} %s\n" "$*"
}

log_warn() {
  printf "${_YELLOW}[WARN]${_RESET} %s\n" "$*"
}

log_error() {
  printf "${_RED}[ERROR]${_RESET} %s\n" "$*" >&2
}

log_manual() {
  printf "${_MAGENTA}[MANUAL STEP]${_RESET} %s\n" "$*"
  MANUAL_STEPS+=("$*")
}

log_section() {
  printf "\n${_BLUE}══════════════════════════════════════════${_RESET}\n"
  printf "${_BLUE} %s${_RESET}\n" "$*"
  printf "${_BLUE}══════════════════════════════════════════${_RESET}\n\n"
}

# ── Directory helpers ────────────────────────────────────────────────
ensure_dir() {
  mkdir -p "$1"
}

# ── File copy helpers ────────────────────────────────────────────────

# Copy a file from the repo to the system (for install scripts)
# Usage: copy_to_system "repo/relative/path" "/absolute/system/path"
copy_to_system() {
  local src="$1"
  local dest="$2"
  if [[ -f "$src" ]]; then
    ensure_dir "$(dirname "$dest")"
    cp "$src" "$dest"
    log_info "Copied $src → $dest"
  else
    log_warn "Source not found: $src (skipping)"
  fi
}

# Copy a file from the system to the repo (for backup scripts)
# Usage: copy_to_repo "/absolute/system/path" "repo/relative/path"
copy_to_repo() {
  local src="$1"
  local dest="$2"
  if [[ -f "$src" ]]; then
    ensure_dir "$(dirname "$dest")"
    cp "$src" "$dest"
    log_info "Backed up $src → $dest"
  else
    log_warn "Source not found: $src (skipping)"
  fi
}

# ── Directory sync helpers ───────────────────────────────────────────

# Sync a directory from system to repo (copies all files, excludes .DS_Store)
# Removes files from dest that no longer exist in source.
# Usage: sync_dir_to_repo "/source/dir" "/repo/dest/dir"
sync_dir_to_repo() {
  local src="$1"
  local dest="$2"
  if [[ -d "$src" ]]; then
    ensure_dir "$dest"
    rsync -a --delete --exclude='.DS_Store' "$src/" "$dest/"
    log_info "Synced $src → $dest"
  else
    log_warn "Source directory not found: $src (skipping)"
  fi
}

# Sync a directory from repo to system (for install/restore)
# Usage: sync_dir_to_system "/repo/dir" "/system/dest/dir"
sync_dir_to_system() {
  local src="$1"
  local dest="$2"
  if [[ -d "$src" ]]; then
    ensure_dir "$dest"
    rsync -a --delete --exclude='.DS_Store' "$src/" "$dest/"
    log_info "Restored $src → $dest"
  else
    log_warn "Source directory not found: $src (skipping)"
  fi
}

# ── Command checks ──────────────────────────────────────────────────
command_exists() {
  command -v "$1" &>/dev/null
}

require_command() {
  if ! command_exists "$1"; then
    log_error "Required command not found: $1"
    exit 1
  fi
}

# ── Summary printer ─────────────────────────────────────────────────
print_manual_steps() {
  if [[ ${#MANUAL_STEPS[@]} -eq 0 ]]; then
    log_info "No manual steps required!"
    return
  fi
  log_section "MANUAL STEPS REQUIRED"
  for i in "${!MANUAL_STEPS[@]}"; do
    printf "${_MAGENTA}  %d.${_RESET} %s\n" "$((i + 1))" "${MANUAL_STEPS[$i]}"
  done
  echo ""
}

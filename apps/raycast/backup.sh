#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../.." && pwd)/_helpers.sh"

log_section "Raycast — Backup"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Raycast's scheduled export writes here, outside the repo. Exporting straight
# into the repo leaves an untracked file that auto-commit.sh stashes away before
# switching to the device branch, so the export never gets committed.
RAYCAST_EXPORT_DIR="$HOME/Library/Application Support/dotfiles/raycast-exports"
REPO_EXPORT="$SCRIPT_DIR/Raycast.rayconfig"

if [[ ! -d "$RAYCAST_EXPORT_DIR" ]]; then
  log_warn "Raycast export folder not found: $RAYCAST_EXPORT_DIR (skipping)"
  exit 0
fi

latest=""
for export_file in "$RAYCAST_EXPORT_DIR"/*.rayconfig; do
  [[ -f "$export_file" ]] || continue
  if [[ -z "$latest" || "$export_file" -nt "$latest" ]]; then
    latest="$export_file"
  fi
done

if [[ -z "$latest" ]]; then
  log_warn "No .rayconfig exports in $RAYCAST_EXPORT_DIR (skipping)"
  exit 0
fi

if [[ -f "$REPO_EXPORT" ]] && cmp -s "$latest" "$REPO_EXPORT"; then
  log_info "Raycast export unchanged ($(basename "$latest"))."
  exit 0
fi

copy_to_repo "$latest" "$REPO_EXPORT"
log_info "Raycast export backed up."

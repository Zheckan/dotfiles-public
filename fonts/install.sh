#!/usr/bin/env bash
# fonts/install.sh — Restore non-cask fonts from fonts/user/ into ~/Library/Fonts/
#
# Cask-managed fonts (Geist, GeistMono, etc.) come from apps/Brewfile via
# apps/install.sh. This script only handles the user-backed files that have
# no Homebrew equivalent.

source "$(cd "$(dirname "$0")/.." && pwd)/_helpers.sh"

FONTS_SRC="$DOTFILES_DIR/fonts/user"
FONTS_DEST="$HOME/Library/Fonts"

log_info "Cask-based fonts are installed via apps/Brewfile (see apps/install.sh)."

if [[ ! -d "$FONTS_SRC" ]]; then
  log_info "No user-backed fonts to restore: $FONTS_SRC does not exist (skipping)."
  exit 0
fi

# Count restorable files without matching .DS_Store.
shopt -s nullglob
files=("$FONTS_SRC"/*.ttf "$FONTS_SRC"/*.otf "$FONTS_SRC"/*.ttc)
shopt -u nullglob

if [[ ${#files[@]} -eq 0 ]]; then
  log_info "No user-backed fonts to restore: $FONTS_SRC is empty (skipping)."
  exit 0
fi

ensure_dir "$FONTS_DEST"

# --ignore-existing so fresh cask-installed files (which may have identical
# basenames) are never clobbered by possibly-stale copies in the repo.
rsync -a --ignore-existing --exclude='.DS_Store' "$FONTS_SRC/" "$FONTS_DEST/"
log_info "Restored ${#files[@]} user-backed font file(s) into $FONTS_DEST"

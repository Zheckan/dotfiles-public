#!/usr/bin/env bash
# fonts/backup.sh — Back up non-cask fonts from ~/Library/Fonts/ into fonts/user/
#
# Fonts covered by a cask in apps/Brewfile are skipped — Homebrew is the
# source of truth for those. Everything else (e.g. cambria.ttf) is copied
# into fonts/user/ so it survives a fresh-machine restore.
#
# Matching uses a family stem (e.g. "geist", "geistmono", "cambria") rather
# than exact basenames, so static .ttf files and variable .otf files from
# the same family are both treated as cask-owned.

source "$(cd "$(dirname "$0")/.." && pwd)/_helpers.sh"

FONTS_SRC="$HOME/Library/Fonts"
FONTS_DEST="$DOTFILES_DIR/fonts/user"
BREWFILE="$DOTFILES_DIR/apps/Brewfile"

if [[ ! -d "$FONTS_SRC" ]]; then
  log_warn "Source directory not found: $FONTS_SRC (skipping)"
  exit 0
fi

# family_stem: canonical family key from a font filename.
#   Geist-Black.ttf          -> geist
#   Geist-BlackItalic.otf    -> geist
#   Geist[wght].ttf          -> geist
#   GeistMono-Bold.ttf       -> geistmono
#   cambria.ttf              -> cambria
family_stem() {
  local name="$1"
  name="${name%.*}"        # strip extension
  name="${name%%\[*}"      # strip [wght] / [ital] variable-axis tags
  name="${name%%-*}"       # strip weight/style suffix after first dash
  printf '%s' "$name" | tr '[:upper:]' '[:lower:]'
}

# ── Collect family stems owned by installed font casks ───────────────

declare -a CASK_FAMILIES=()

if command_exists brew && [[ -f "$BREWFILE" ]]; then
  while IFS= read -r cask; do
    [[ -n "$cask" ]] || continue
    while IFS= read -r artifact; do
      [[ -n "$artifact" ]] || continue
      stem="$(family_stem "$(basename "$artifact")")"
      [[ -n "$stem" ]] && CASK_FAMILIES+=("$stem")
    done < <(brew ls --cask "$cask" 2>/dev/null | grep -E '\.(ttf|otf|ttc)$')
  done < <(grep -E '^cask "font-' "$BREWFILE" | sed -E 's/.*"(font-[^"]+)".*/\1/')
fi

is_cask_family() {
  local stem="$1"
  local owned
  for owned in "${CASK_FAMILIES[@]:-}"; do
    [[ "$stem" == "$owned" ]] && return 0
  done
  return 1
}

# ── Walk user fonts, copy anything whose family isn't cask-owned ─────

ensure_dir "$FONTS_DEST"

copied=0
skipped_cask=0
total=0

shopt -s nullglob
for src in "$FONTS_SRC"/*.ttf "$FONTS_SRC"/*.otf "$FONTS_SRC"/*.ttc; do
  total=$((total + 1))
  name="$(basename "$src")"
  stem="$(family_stem "$name")"
  if is_cask_family "$stem"; then
    skipped_cask=$((skipped_cask + 1))
    continue
  fi
  copy_to_repo "$src" "$FONTS_DEST/$name"
  copied=$((copied + 1))
done
shopt -u nullglob

log_info "Fonts: $copied copied, $skipped_cask covered by cask, $total total in $FONTS_SRC"

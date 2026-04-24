#!/usr/bin/env bash
# cli/shell/install.sh — Install Zsh config, Oh My Zsh, plugins, and theme

source "$(cd "$(dirname "$0")/../.." && pwd)/_helpers.sh"

SHELL_DIR="$DOTFILES_DIR/cli/shell"
OMZ_DIR="$HOME/.oh-my-zsh"
OMZ_CUSTOM="$OMZ_DIR/custom"
OMZ_PLUGINS="$OMZ_CUSTOM/plugins"
OMZ_THEMES="$OMZ_CUSTOM/themes"

# ── Oh My Zsh ──────────────────────────────────────────────────────────

if [[ ! -d "$OMZ_DIR" ]]; then
  log_info "Installing Oh My Zsh..."
  RUNZSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  log_info "Oh My Zsh installed."
else
  log_info "Oh My Zsh already installed."
fi

# ── Plugins ────────────────────────────────────────────────────────────

ensure_dir "$OMZ_PLUGINS"

declare -A plugins=(
  [zsh-autosuggestions]="https://github.com/zsh-users/zsh-autosuggestions.git"
  [zsh-syntax-highlighting]="https://github.com/zsh-users/zsh-syntax-highlighting.git"
  [zsh-shift-select]="https://github.com/jirutka/zsh-shift-select.git"
)

for plugin in "${!plugins[@]}"; do
  plugin_dir="$OMZ_PLUGINS/$plugin"
  if [[ -d "$plugin_dir" ]]; then
    log_info "Plugin $plugin already installed."
  else
    log_info "Cloning $plugin..."
    git clone --depth=1 "${plugins[$plugin]}" "$plugin_dir"
    log_info "Plugin $plugin installed."
  fi
done

# ── Shell dotfiles ─────────────────────────────────────────────────────

copy_to_system "$SHELL_DIR/.zshrc" "$HOME/.zshrc"
copy_to_system "$SHELL_DIR/.zshenv" "$HOME/.zshenv"
copy_to_system "$SHELL_DIR/.zprofile" "$HOME/.zprofile"

# ── Theme ──────────────────────────────────────────────────────────────

ensure_dir "$OMZ_THEMES"

if [[ -d "$SHELL_DIR/themes" ]]; then
  for theme_file in "$SHELL_DIR/themes/"*.zsh-theme; do
    [[ -f "$theme_file" ]] || continue
    theme_name="$(basename "$theme_file")"
    copy_to_system "$theme_file" "$OMZ_THEMES/$theme_name"
  done
else
  log_warn "No themes directory found in $SHELL_DIR — skipping."
fi

log_info "Shell configuration installed."

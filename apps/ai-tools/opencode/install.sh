#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

log_section "OpenCode — Install"

# Install OpenCode if missing
if command_exists opencode; then
  log_info "OpenCode is already installed."
else
  log_info "Installing OpenCode..."
  curl -fsSL https://opencode.ai/install | bash
fi

# Copy config
copy_to_system "$SCRIPT_DIR/opencode.json" "$HOME/.config/opencode/opencode.json"

# Copy instructions
if [[ -d "$SCRIPT_DIR/instructions" ]]; then
  ensure_dir "$HOME/.config/opencode/instructions"
  for f in "$SCRIPT_DIR/instructions"/*; do
    [[ -f "$f" ]] && cp "$f" "$HOME/.config/opencode/instructions/"
  done
  log_info "Copied OpenCode instructions"
fi

log_manual "Run 'opencode' to authenticate"

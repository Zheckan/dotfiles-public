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

# The backed-up config references credentials as {env:VAR} instead of storing
# them inline, so a restored machine needs those variables exported before the
# affected MCP servers will authenticate.
if [[ -f "$HOME/.config/opencode/opencode.json" ]]; then
  ENV_REFS="$(grep -oE '\{env:[A-Za-z0-9_]+\}' "$HOME/.config/opencode/opencode.json" 2>/dev/null \
    | sed -E 's/^\{env:(.+)\}$/\1/' | sort -u | tr '\n' ' ' || true)"
  ENV_REFS="${ENV_REFS%"${ENV_REFS##*[![:space:]]}"}"
  if [[ -n "$ENV_REFS" ]]; then
    log_manual "Export credentials referenced by opencode.json: $ENV_REFS"
  fi
fi

log_manual "Run 'opencode' to authenticate"

#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"

log_section "Yarn — Install"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

copy_to_system "$SCRIPT_DIR/.yarnrc.yml" "$HOME/.yarnrc.yml"

#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../.." && pwd)/_helpers.sh"

log_section "Yarn — Backup"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

copy_to_repo "$HOME/.yarnrc.yml" "$SCRIPT_DIR/.yarnrc.yml"

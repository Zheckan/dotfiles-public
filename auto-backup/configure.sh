#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v python3 &>/dev/null; then
  printf 'configure.sh: python3 is required for the setup wizard.\n' >&2
  exit 1
fi

exec python3 "$SCRIPT_DIR/configure.py" "$@"

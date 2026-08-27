#!/usr/bin/env bash
# test-review-adapters.sh — Unit tests for the reviewer output parsers.
#
# These run offline against fixtures: no reviewer CLI is invoked and no
# credentials are needed, so CI can execute them. Live end-to-end behaviour
# (does `opencode run` actually return a verdict?) is verified by hand.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  local what="$3"
  [[ "$expected" == "$actual" ]] \
    || fail "$what: expected $(printf '%q' "$expected"), got $(printf '%q' "$actual")"
}

# Pull in the function definitions without running the backup flow.
DOTFILES_AUTOBACKUP_SOURCE_ONLY=true \
  DOTFILES_AUTOBACKUP_CONFIG_FILE="$SCRIPT_DIR/config.example.toml" \
  source "$SCRIPT_DIR/auto-commit.sh"

declare -F parse_opencode_json_review >/dev/null \
  || fail "parse_opencode_json_review is not defined"
declare -F parse_agy_stream_review >/dev/null \
  || fail "parse_agy_stream_review is not defined"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

events="$work_dir/events.jsonl"
review="$work_dir/review.txt"

# ── Assistant prose is extracted, non-text events ignored ────────────
cat > "$events" <<'JSON'
{"type":"step_start","part":{"id":"prt_1","type":"step-start"}}
{"type":"text","part":{"id":"prt_2","type":"text","text":"APPROVED\n\nLooks fine."}}
{"type":"step_finish","part":{"id":"prt_3","tokens":{"total":10}}}
JSON
parse_opencode_json_review "$events" "$review"
assert_equals "APPROVED

Looks fine." "$(cat "$review")" "extracts text events only"

# ── Multiple distinct parts are joined in arrival order ──────────────
cat > "$events" <<'JSON'
{"type":"text","part":{"id":"prt_a","type":"text","text":"CHANGES_REQUESTED"}}
{"type":"text","part":{"id":"prt_b","type":"text","text":"Secret detected."}}
JSON
parse_opencode_json_review "$events" "$review"
assert_equals "CHANGES_REQUESTED
Secret detected." "$(cat "$review")" "joins distinct parts in order"

# ── A part re-emitted as it streams keeps only its final value ───────
# Guards against concatenating a growing part with its own prefixes.
cat > "$events" <<'JSON'
{"type":"text","part":{"id":"prt_x","type":"text","text":"APP"}}
{"type":"text","part":{"id":"prt_x","type":"text","text":"APPROVED"}}
JSON
parse_opencode_json_review "$events" "$review"
assert_equals "APPROVED" "$(cat "$review")" "de-duplicates a streamed part by id"

# ── Malformed lines and blanks are skipped, not fatal ────────────────
cat > "$events" <<'JSON'
not json at all

{"type":"text","part":{"id":"prt_ok","type":"text","text":"APPROVED"}}
{"broken":
JSON
parse_opencode_json_review "$events" "$review"
assert_equals "APPROVED" "$(cat "$review")" "tolerates malformed lines"

# ── No assistant text yields empty output ────────────────────────────
# The adapter turns this into exit 65 rather than a silent empty approval.
cat > "$events" <<'JSON'
{"type":"step_start","part":{"id":"prt_1"}}
{"type":"step_finish","part":{"id":"prt_2"}}
JSON
parse_opencode_json_review "$events" "$review"
assert_equals "" "$(cat "$review")" "empty when no text events"

# ── AGY extracts only a successful final result ─────────────────────
cat > "$events" <<'JSON'
{"event":"init","conversation_id":"conversation-1"}
{"event":"step_update","step_update":{"step_type":"agent_response","text_delta":"APP"}}
{"event":"result","result":{"status":"SUCCESS","response":"APPROVED\n\n### Summary\nClean backup."}}
JSON
parse_agy_stream_review "$events" "$review"
assert_equals "APPROVED

### Summary
Clean backup." "$(cat "$review")" "extracts AGY success result"

# ── AGY error and malformed streams fail closed ─────────────────────
cat > "$events" <<'JSON'
{"event":"result","result":{"status":"ERROR","response":"","error":"authentication required"}}
JSON
if parse_agy_stream_review "$events" "$review"; then
  fail "AGY error result should fail"
fi

printf '%s\n' 'not json' > "$events"
if parse_agy_stream_review "$events" "$review"; then
  fail "malformed AGY stream should fail"
fi

printf 'PASS: reviewer output parsers\n'

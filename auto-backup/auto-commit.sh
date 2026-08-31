#!/usr/bin/env bash
# Auto-commit script — called by LaunchAgent or Apple Shortcut
# Sets up PATH for non-interactive environments (Shortcuts, launchd)

# Load Homebrew and user PATH
eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null)" || true
NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  export NVM_DIR
  # shellcheck source=/dev/null
  source "$NVM_DIR/nvm.sh" --no-use
  nvm use --silent default > /dev/null 2>&1 || true
fi
export PATH="/usr/local/bin:$HOME/.local/bin:$HOME/.opencode/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

split_csv_lines() {
  local csv="$1"
  local item

  while :; do
    if [[ "$csv" == *,* ]]; then
      item="${csv%%,*}"
      csv="${csv#*,}"
    else
      item="$csv"
      csv=
    fi

    item="$(trim "$item")"
    printf '%s\n' "$item"

    [[ -z "$csv" ]] && break
  done
}

config_error() {
  printf 'auto-commit: invalid config: %s\n' "$*" >&2
  exit 2
}

shell_single_quote() {
  local value="$1"
  value="${value//\'/\'\\\'\'}"
  printf "'%s'" "$value"
}

run_terminal_notifier() {
  local output status

  if output="$(terminal-notifier "$@" 2>&1)"; then
    status=0
  else
    status=$?
  fi

  if [[ "$output" == *"didGrant:0"* || "$output" == *"hasError:1"* ]]; then
    printf 'auto-commit: terminal-notifier denied notification access\n' >&2
    return 1
  fi
  if [[ $status -ne 0 ]]; then
    output="$(printf '%s' "$output" | tr '\n' ' ' | cut -c1-240)"
    printf 'auto-commit: terminal-notifier failed (exit=%s): %s\n' "$status" "$output" >&2
    return 1
  fi

  return 0
}

run_osascript_notification() {
  local message="$1"
  local sound="${2:-}"
  local output status

  command -v osascript &>/dev/null || return 127
  if output="$(osascript - "$message" "$sound" 2>&1 <<'APPLESCRIPT'
on run argv
  set notificationMessage to item 1 of argv
  set notificationSound to item 2 of argv
  if notificationSound is "" then
    display notification notificationMessage with title "Dotfiles Backup"
  else
    display notification notificationMessage with title "Dotfiles Backup" sound name notificationSound
  end if
end run
APPLESCRIPT
  )"; then
    return 0
  else
    status=$?
  fi

  output="$(printf '%s' "$output" | tr '\n' ' ' | cut -c1-240)"
  printf 'auto-commit: osascript notification failed (exit=%s): %s\n' "$status" "$output" >&2
  return "$status"
}

deliver_notification() {
  local message="$1"
  local url="${2:-}"
  local sound="${3:-}"
  local args=(-title "Dotfiles Backup" -message "$message")

  [[ -n "$url" ]] && args+=(-open "$url")
  [[ -n "$sound" ]] && args+=(-sound "$sound")

  if command -v terminal-notifier &>/dev/null; then
    run_terminal_notifier "${args[@]}" && return 0
  fi
  run_osascript_notification "$message" "$sound" && return 0

  printf 'auto-commit: macOS notification delivery failed; run %s --test-notification\n' "$SCRIPT_DIR/auto-commit.sh" >&2
  return 1
}

test_notification_delivery() {
  local message="Dotfiles backup test notification"

  if deliver_notification "$message" "" "Glass"; then
    printf 'Test notification sent. If it did not appear, enable notifications for terminal-notifier or osascript in System Settings.\n'
    return 0
  fi

  printf 'Test notification failed. Enable notifications for terminal-notifier or osascript in System Settings.\n' >&2
  return 1
}

if [[ "$#" -eq 1 && "$1" == "--test-notification" ]]; then
  test_notification_delivery
  exit $?
fi

notify_setup_required() {
  local setup_command="$SCRIPT_DIR/configure.sh"
  local message="Auto-backup is not configured. Run: $setup_command"
  local copy_action

  if [[ "${DOTFILES_AUTOBACKUP_SOURCE_ONLY:-false}" != "true" ]]; then
    if command -v terminal-notifier &>/dev/null; then
      copy_action="/usr/bin/printf '%s' $(shell_single_quote "$setup_command") | /usr/bin/pbcopy"
      run_terminal_notifier \
        -title "Dotfiles Backup" \
        -message "Auto-backup is not configured. Click to copy the setup command." \
        -subtitle "$setup_command" \
        -execute "$copy_action" \
        -sound Basso ||
        run_osascript_notification "$message" "Basso" || true
    else
      run_osascript_notification "$message" "Basso" || true
    fi
  fi
  printf 'auto-commit: %s\n' "$message" >&2
}

notify_deprecated_reviewer_flag() {
  local flag="$1"
  local setup_command="$SCRIPT_DIR/configure.sh"
  local message="Deprecated reviewer flag: $flag. Run: $setup_command"
  local copy_action

  if [[ "${DOTFILES_AUTOBACKUP_SOURCE_ONLY:-false}" != "true" ]]; then
    if command -v terminal-notifier &>/dev/null; then
      copy_action="/usr/bin/printf '%s' $(shell_single_quote "$setup_command") | /usr/bin/pbcopy"
      run_terminal_notifier \
        -title "Dotfiles Backup" \
        -message "Deprecated reviewer flag: $flag. Click to copy the migration command." \
        -subtitle "$setup_command" \
        -execute "$copy_action" \
        -sound Basso ||
        run_osascript_notification "$message" "Basso" || true
    else
      run_osascript_notification "$message" "Basso" || true
    fi
  fi
  printf 'auto-commit: %s\n' "$message" >&2
}

load_toml_config() {
  local file="$1"
  local output_file error_file key value detail

  command -v python3 &>/dev/null ||
    config_error "python3 is required to read auto-backup/config.local.toml"
  output_file="$(mktemp)"
  error_file="$(mktemp)"
  if ! python3 "$SCRIPT_DIR/config.py" "$file" > "$output_file" 2> "$error_file"; then
    detail="$(<"$error_file")"
    rm -f "$output_file" "$error_file"
    config_error "$detail"
  fi

  while IFS=$'\t' read -r key value; do
    case "$key" in
      DOTFILES_AUTOBACKUP_MODE|DOTFILES_AUTOBACKUP_REBASE|DOTFILES_AUTOBACKUP_REVIEW|DOTFILES_REVIEWERS|DOTFILES_REVIEW_CLAUDE_MODELS|DOTFILES_REVIEW_CODEX_MODELS|DOTFILES_REVIEW_AGY_MODELS|DOTFILES_REVIEW_OPENCODE_MODELS|DOTFILES_REVIEW_OPENCODE_GO_API_MODELS|DOTFILES_REVIEW_CURSOR_MODELS|DOTFILES_REVIEW_OLLAMA_MODELS)
        printf -v "$key" '%s' "$value"
        ;;
      *)
        rm -f "$output_file" "$error_file"
        config_error "config parser returned unsupported key '$key'"
        ;;
    esac
  done < "$output_file"
  rm -f "$output_file" "$error_file"
}

CONFIG_FILE="${DOTFILES_AUTOBACKUP_CONFIG_FILE:-$SCRIPT_DIR/config.local.toml}"
if [[ ! -f "$CONFIG_FILE" ]]; then
  notify_setup_required
  exit 2
fi
load_toml_config "$CONFIG_FILE"

OPENCODE_GO_ENV_FILE="${DOTFILES_OPENCODE_GO_ENV_FILE:-$SCRIPT_DIR/.env}"
validate_opencode_go_secret_file() {
  local detail

  [[ -e "$OPENCODE_GO_ENV_FILE" ]] || return 0
  if [[ "$OPENCODE_GO_ENV_FILE" == "$SCRIPT_DIR/.env" ]] &&
    git -C "$DOTFILES_REPO_DIR" ls-files --error-unmatch -- "auto-backup/.env" &>/dev/null; then
    config_error "auto-backup/.env contains a secret and must not be tracked"
  fi
  if ! detail="$(python3 "$SCRIPT_DIR/opencode_go.py" read-key "$OPENCODE_GO_ENV_FILE" 2>&1 > /dev/null)"; then
    config_error "$detail"
  fi
}
validate_opencode_go_secret_file

DOTFILES_AUTOBACKUP_MODE="${DOTFILES_AUTOBACKUP_MODE:-}"
DOTFILES_AUTOBACKUP_REBASE="${DOTFILES_AUTOBACKUP_REBASE:-}"
DOTFILES_AUTOBACKUP_REVIEW="${DOTFILES_AUTOBACKUP_REVIEW:-}"
DOTFILES_REVIEWERS="${DOTFILES_REVIEWERS:-}"
DOTFILES_REVIEW_CLAUDE_MODELS="${DOTFILES_REVIEW_CLAUDE_MODELS:-}"
DOTFILES_REVIEW_CODEX_MODELS="${DOTFILES_REVIEW_CODEX_MODELS:-}"
DOTFILES_REVIEW_AGY_MODELS="${DOTFILES_REVIEW_AGY_MODELS:-}"
DOTFILES_REVIEW_OPENCODE_MODELS="${DOTFILES_REVIEW_OPENCODE_MODELS:-}"
DOTFILES_REVIEW_OPENCODE_GO_API_MODELS="${DOTFILES_REVIEW_OPENCODE_GO_API_MODELS:-}"

# ── Flags ─────────────────────────────────────────────────────────
# --main-pc    : Full flow — rebase, backup, review, PR, merge
# --pr-only    : Same as --main-pc but without merge
# --no-rebase  : Skip rebase on main (combinable with above)
# --no-review  : Skip AI review (combinable with above)
# --test       : Test mode — stay on current branch, push, create PR, review (no backup, no merge)
# --test-notification: Send one notification without loading backup config
MODE_FLAG=""
REBASE_FLAG=""
REVIEW_FLAG=""
for arg in "$@"; do
  case "$arg" in
    --main-pc) MODE_FLAG="main-pc" ;;
    --pr-only) MODE_FLAG="pr-only" ;;
    --no-rebase) REBASE_FLAG="false" ;;
    --no-review) REVIEW_FLAG="false" ;;
    --test) MODE_FLAG="test" ;;
    --claude|--codex|--agy|--gemini|--opencode|--opencode-go-api|--cursor|--ollama)
      notify_deprecated_reviewer_flag "$arg"
      config_error "reviewer flags were removed; run auto-backup/configure.sh to select and order reviewers"
      ;;
    *) config_error "unknown option '$arg'" ;;
  esac
done

[[ -n "$MODE_FLAG" ]] && DOTFILES_AUTOBACKUP_MODE="$MODE_FLAG"
[[ -n "$REBASE_FLAG" ]] && DOTFILES_AUTOBACKUP_REBASE="$REBASE_FLAG"
[[ -n "$REVIEW_FLAG" ]] && DOTFILES_AUTOBACKUP_REVIEW="$REVIEW_FLAG"

validate_boolean_config() {
  local name="$1"
  local value="$2"

  case "$value" in
    true|false) ;;
    *) config_error "$name must be true or false (got: $value)" ;;
  esac
}

validate_csv_nonempty() {
  local name="$1"
  local value="$2"
  local item

  [[ -n "$(trim "$value")" ]] || config_error "$name must not be empty"
  case "$value" in
    *,,*|*,|,*) config_error "$name must be a comma-separated list without empty items (got: $value)" ;;
  esac

  while IFS= read -r item; do
    [[ -n "$item" ]] || config_error "$name must not contain empty items"
  done < <(split_csv_lines "$value")
}

validate_reviewer_name() {
  local reviewer="$1"

  case "$reviewer" in
    claude|codex|agy|opencode|opencode-go-api|cursor|ollama) ;;
    *) config_error "unknown reviewer '$reviewer' (allowed: claude, codex, agy, opencode, opencode-go-api, cursor, ollama)" ;;
  esac
}

validate_reviewers_config() {
  local reviewer

  validate_csv_nonempty "DOTFILES_REVIEWERS" "$DOTFILES_REVIEWERS"
  while IFS= read -r reviewer; do
    validate_reviewer_name "$reviewer"
  done < <(split_csv_lines "$DOTFILES_REVIEWERS")
}

model_list_name_for_reviewer() {
  case "$1" in
    claude) printf 'DOTFILES_REVIEW_CLAUDE_MODELS' ;;
    codex) printf 'DOTFILES_REVIEW_CODEX_MODELS' ;;
    agy) printf 'DOTFILES_REVIEW_AGY_MODELS' ;;
    opencode) printf 'DOTFILES_REVIEW_OPENCODE_MODELS' ;;
    opencode-go-api) printf 'DOTFILES_REVIEW_OPENCODE_GO_API_MODELS' ;;
    cursor) printf 'DOTFILES_REVIEW_CURSOR_MODELS' ;;
    ollama) printf 'DOTFILES_REVIEW_OLLAMA_MODELS' ;;
  esac
}

model_list_value_for_reviewer() {
  case "$1" in
    claude) printf '%s' "${DOTFILES_REVIEW_CLAUDE_MODELS:-}" ;;
    codex) printf '%s' "${DOTFILES_REVIEW_CODEX_MODELS:-}" ;;
    agy) printf '%s' "${DOTFILES_REVIEW_AGY_MODELS:-}" ;;
    opencode) printf '%s' "${DOTFILES_REVIEW_OPENCODE_MODELS:-}" ;;
    opencode-go-api) printf '%s' "${DOTFILES_REVIEW_OPENCODE_GO_API_MODELS:-}" ;;
    cursor) printf '%s' "${DOTFILES_REVIEW_CURSOR_MODELS:-}" ;;
    ollama) printf '%s' "${DOTFILES_REVIEW_OLLAMA_MODELS:-}" ;;
  esac
}

validate_selected_model_lists() {
  local reviewer name value

  while IFS= read -r reviewer; do
    [[ -n "$reviewer" ]] || continue
    name="$(model_list_name_for_reviewer "$reviewer")"
    value="$(model_list_value_for_reviewer "$reviewer")"
    [[ -z "$(trim "$value")" ]] || validate_csv_nonempty "$name" "$value"
  done < <(split_csv_lines "$DOTFILES_REVIEWERS")
}

validate_config() {
  case "$DOTFILES_AUTOBACKUP_MODE" in
    device-only|main-pc|pr-only|test) ;;
    *) config_error "DOTFILES_AUTOBACKUP_MODE must be device-only, main-pc, pr-only, or test (got: $DOTFILES_AUTOBACKUP_MODE)" ;;
  esac

  validate_boolean_config "DOTFILES_AUTOBACKUP_REBASE" "$DOTFILES_AUTOBACKUP_REBASE"
  validate_boolean_config "DOTFILES_AUTOBACKUP_REVIEW" "$DOTFILES_AUTOBACKUP_REVIEW"
  [[ "$DOTFILES_AUTOBACKUP_REVIEW" == "false" ]] && return 0

  validate_reviewers_config
  validate_selected_model_lists
}

validate_config

MAIN_PC=false
PR_ONLY=false
TEST_MODE=false
case "$DOTFILES_AUTOBACKUP_MODE" in
  main-pc) MAIN_PC=true ;;
  pr-only) PR_ONLY=true ;;
  test) TEST_MODE=true ;;
esac

NO_REBASE=false
NO_REVIEW=false
[[ "$DOTFILES_AUTOBACKUP_REBASE" == "false" ]] && NO_REBASE=true
[[ "$DOTFILES_AUTOBACKUP_REVIEW" == "false" ]] && NO_REVIEW=true

DEFAULT_REPO_DIR="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/.." && pwd))"
DOTFILES_REPO_DIR="${DOTFILES_REPO_DIR:-$DEFAULT_REPO_DIR}"
DOTFILES_LOG_DIR="${DOTFILES_LOG_DIR:-$HOME/Library/Logs/dotfiles}"
DOTFILES_AUTOBACKUP_LOCKFILE="${DOTFILES_AUTOBACKUP_LOCKFILE:-/tmp/dotfiles-autocommit.lock}"

normalize_github_repo() {
  local value="$1"

  value="${value#https://github.com/}"
  value="${value#http://github.com/}"
  value="${value#git@github.com:}"
  value="${value%.git}"
  value="${value#/}"

  printf '%s' "$value"
}

infer_github_repo() {
  local remote_url
  remote_url=$(git -C "$DOTFILES_REPO_DIR" remote get-url origin 2>/dev/null || true)
  [[ -n "$remote_url" ]] || return 0

  normalize_github_repo "$remote_url"
}

DOTFILES_GITHUB_REPO="${DOTFILES_GITHUB_REPO:-$(infer_github_repo)}"
DOTFILES_GITHUB_REPO="$(normalize_github_repo "$DOTFILES_GITHUB_REPO")"

github_url() {
  local path="$1"
  [[ -n "$DOTFILES_GITHUB_REPO" ]] || return 0
  printf 'https://github.com/%s/%s' "$DOTFILES_GITHUB_REPO" "$path"
}

# ── Notifications (macOS) ─────────────────────────────────────────
# Usage: notify_error "message" ["url"]
# Usage: notify_success "message" ["url"]
notify_error() {
  local msg="$1" url="${2:-}"
  deliver_notification "$msg" "$url" "Basso" || true
  echo "✗ $msg" >&2
}

notify_success() {
  local msg="$1" url="${2:-}"
  deliver_notification "$msg" "$url" "" || true
}

# ── PR Review (AI reviewer adapters) ─────────────────────────────
# Reviews the PR diff before allowing merge. Returns 0 if approved, 1 otherwise.
# Exit 78 marks a deterministic local adapter failure. Trying another model in
# the same adapter cannot fix it, so review_pr moves to the next reviewer.
REVIEW_EXIT_NONRETRYABLE=78

reviewer_display_name() {
  case "$1" in
    claude) printf 'Claude' ;;
    codex) printf 'Codex' ;;
    agy) printf 'AGY' ;;
    opencode) printf 'OpenCode' ;;
    opencode-go-api) printf 'OpenCode Go direct API' ;;
    cursor) printf 'Cursor' ;;
    ollama) printf 'Ollama' ;;
    *) printf '%s' "$1" ;;
  esac
}

reviewer_url() {
  case "$1" in
    claude) printf 'https://claude.com/claude-code' ;;
    codex) printf 'https://developers.openai.com/codex' ;;
    agy) printf 'https://antigravity.google/docs/cli/overview/' ;;
    opencode) printf 'https://opencode.ai' ;;
    opencode-go-api) printf 'https://opencode.ai/docs/go/' ;;
    cursor) printf 'https://cursor.com' ;;
    ollama) printf 'https://ollama.com' ;;
  esac
}

reviewer_command() {
  case "$1" in
    claude) printf 'claude' ;;
    codex) printf 'codex' ;;
    agy) printf 'agy' ;;
    opencode) printf 'opencode' ;;
    opencode-go-api) printf 'python3' ;;
    cursor) printf 'cursor' ;;
    ollama) printf 'ollama' ;;
  esac
}

configured_reviewers() {
  if [[ -n "${DOTFILES_REVIEWERS:-}" ]]; then
    split_csv_lines "$DOTFILES_REVIEWERS"
    return 0
  fi
}

models_for_reviewer() {
  local reviewer="$1"
  local _prompt_file="$2"
  local raw=""

  case "$reviewer" in
    claude) raw="${DOTFILES_REVIEW_CLAUDE_MODELS:-}" ;;
    codex) raw="${DOTFILES_REVIEW_CODEX_MODELS:-}" ;;
    agy) raw="${DOTFILES_REVIEW_AGY_MODELS:-}" ;;
    opencode) raw="${DOTFILES_REVIEW_OPENCODE_MODELS:-}" ;;
    opencode-go-api) raw="${DOTFILES_REVIEW_OPENCODE_GO_API_MODELS:-}" ;;
    cursor) raw="${DOTFILES_REVIEW_CURSOR_MODELS:-}" ;;
    ollama) raw="${DOTFILES_REVIEW_OLLAMA_MODELS:-}" ;;
  esac

  if [[ -n "$raw" ]]; then
    split_csv_lines "$raw"
    return 0
  fi

  printf 'default\n'
}

first_review_line() {
  sed '/^[[:space:]]*$/d' | head -1
}

lines_from_array() {
  local item

  for item in "$@"; do
    printf '%s\n' "$item"
  done
}

sanitize_review_detail() {
  if [[ "$#" -gt 0 ]]; then
    printf '%s' "$*"
  else
    cat
  fi | python3 -c '
import json
import re
import sys

text = sys.stdin.read()

def compact_json_detail(value):
    try:
        data = json.loads(value)
    except json.JSONDecodeError:
        return value
    if not isinstance(data, dict):
        return value

    result = str(data.get("result") or data.get("error") or data.get("message") or "").strip()
    status = data.get("api_error_status") or data.get("status")
    if not result:
        return value

    result = re.sub(r"\s+", " ", result).strip()
    if status:
        result = re.sub(r"(?i)\bAPI Error:\s*" + re.escape(str(status)) + r"\s*", "", result).strip()
        result = re.sub(r"(?i)\bInvalid authentication credentials\b\.?", "Invalid authentication credentials", result).strip()
        if result and not result.endswith("."):
            result += "."
        return f"API {status}: {result}"
    return result

text = compact_json_detail(text)
text = re.sub(r"\s+", " ", text).strip()
patterns = [
    r"(?i)\bauthorization\b\s*[:=]\s*bearer\s+[^\s,;]+",
    r"(?i)\bauthorization\b\s*[:=]\s*[^\s,;]+",
    r"(?i)\bbearer\s+[^\s,;]+",
    r"(?i)\b(api[_-]?(?:key|token)|token|password|passwd|secret)\b\s*[:=]\s*[^\s,;]+",
]
for pattern in patterns:
    text = re.sub(pattern, lambda match: re.split(r"[:=\s]+", match.group(0), maxsplit=1)[0] + "=<redacted>", text)
if len(text) > 240:
    text = text[:237].rstrip() + "..."
print(text)
'
}

format_review_fallback_reason() {
  local diagnostics_text="$1"

  printf '%s' "$diagnostics_text" | python3 -c '
import re
import sys

text = sys.stdin.read()
lines = [line.strip() for line in text.splitlines() if line.strip()]
if not lines:
    sys.exit(0)

auth_attempts = []
all_auth = True
for line in lines:
    match = re.match(
        r"^Claude \(`([^`]+)`\): failed, exit=(\d+), API (\d+): (.*)$",
        line,
    )
    if not match:
        all_auth = False
        break
    model, _exit_code, status, detail = match.groups()
    if status != "401" or "authenticat" not in detail.lower():
        all_auth = False
        break
    auth_attempts.append((model, status, detail))

if all_auth and auth_attempts:
    print("Claude authentication failed for all configured models:")
    for model, status, detail in auth_attempts:
        summary = "invalid authentication credentials"
        if "invalid authentication credentials" not in detail.lower():
            summary = detail.rstrip(".")
        print(f"- `{model}`: API {status}, {summary}")
else:
    for line in lines:
        print(f"- {line}")
'
}

normalize_review_output() {
  local input_file="$1"
  local output_file="$2"
  local meta_file="$3"

  python3 - "$input_file" "$output_file" "$meta_file" <<'PY'
import sys

input_file, output_file, meta_file = sys.argv[1:4]
with open(input_file, "r", encoding="utf-8") as fh:
    lines = fh.read().splitlines()

verdict_indexes = [
    index
    for index, line in enumerate(lines)
    if line.strip() in {"APPROVED", "CHANGES_REQUESTED"}
]

if len(verdict_indexes) != 1:
    reason = "missing verdict" if not verdict_indexes else "multiple verdict lines"
    with open(meta_file, "w", encoding="utf-8") as fh:
        fh.write(reason)
    sys.exit(1)

verdict_index = verdict_indexes[0]
verdict = lines[verdict_index].strip()
preface_lines = sum(1 for line in lines[:verdict_index] if line.strip())
normalized = [verdict] + lines[verdict_index + 1 :]

with open(output_file, "w", encoding="utf-8") as fh:
    fh.write("\n".join(normalized))

with open(meta_file, "w", encoding="utf-8") as fh:
    if preface_lines:
        fh.write(f"removed {preface_lines} preface line")
        if preface_lines != 1:
            fh.write("s")
        fh.write(f" before {verdict}")
PY
}

normalize_review_input() {
  python3 -c '
import sys

raw = sys.stdin.buffer.read()
text = raw.decode("utf-8", errors="backslashreplace")
sys.stdout.buffer.write(text.encode("utf-8"))
'
}

write_pr_body() {
  local pr_number="$1"
  local body="$2"
  local tmp_body

  tmp_body="$(mktemp)"
  printf '%s\n' "$body" > "$tmp_body"
  gh pr edit "$pr_number" --body-file "$tmp_body" > /dev/null 2>&1
  rm -f "$tmp_body"
}

review_diagnostics_marker() {
  printf '<!-- dotfiles-auto-review-diagnostics -->'
}

find_review_diagnostics_comment() {
  local pr_number="$1"
  local marker

  [[ -n "$DOTFILES_GITHUB_REPO" ]] || return 0
  marker="$(review_diagnostics_marker)"
  gh api "repos/$DOTFILES_GITHUB_REPO/issues/$pr_number/comments" --paginate \
    --jq ".[] | select(.body | contains(\"$marker\")) | .id" 2>/dev/null | head -1
}

json_body_file() {
  local body_file="$1"
  local json_file="$2"

  python3 - "$body_file" "$json_file" <<'PY'
import json
import sys

body_file, json_file = sys.argv[1:3]
with open(body_file, "r", encoding="utf-8") as fh:
    body = fh.read()
with open(json_file, "w", encoding="utf-8") as fh:
    json.dump({"body": body}, fh)
PY
}

upsert_review_diagnostics_comment() {
  local pr_number="$1"
  local body="$2"
  local comment_id tmp_body tmp_json

  [[ -n "$DOTFILES_GITHUB_REPO" ]] || return 0

  tmp_body="$(mktemp)"
  tmp_json="$(mktemp)"
  printf '%s\n' "$body" > "$tmp_body"
  json_body_file "$tmp_body" "$tmp_json"

  comment_id="$(find_review_diagnostics_comment "$pr_number")"
  if [[ -n "$comment_id" ]]; then
    gh api --method PATCH "repos/$DOTFILES_GITHUB_REPO/issues/comments/$comment_id" --input "$tmp_json" > /dev/null 2>&1 \
      || printf 'WARN: failed to update auto-review diagnostics comment\n' >&2
  else
    gh api --method POST "repos/$DOTFILES_GITHUB_REPO/issues/$pr_number/comments" --input "$tmp_json" > /dev/null 2>&1 \
      || printf 'WARN: failed to create auto-review diagnostics comment\n' >&2
  fi

  rm -f "$tmp_body" "$tmp_json"
}

delete_review_diagnostics_comment() {
  local pr_number="$1"
  local comment_id

  [[ -n "$DOTFILES_GITHUB_REPO" ]] || return 0
  comment_id="$(find_review_diagnostics_comment "$pr_number")"
  [[ -n "$comment_id" ]] || return 0

  gh api --method DELETE "repos/$DOTFILES_GITHUB_REPO/issues/comments/$comment_id" > /dev/null 2>&1 \
    || printf 'WARN: failed to delete stale auto-review diagnostics comment\n' >&2
}

build_review_diagnostics_body() {
  local final_reviewer="$1"
  local final_model="$2"
  local final_actual_model="$3"
  local diagnostics_text="$4"
  local normalizations_text="$5"
  local auxiliary_models="${6:-}"
  local body marker item fallback_reason_text

  marker="$(review_diagnostics_marker)"
  body="$marker
### Auto-review fallback diagnostics

Final reviewer: $final_reviewer (model: \`$final_actual_model\`, configured: \`$final_model\`)"

  if [[ -n "$auxiliary_models" ]]; then
    body="$body
Auxiliary models: \`$auxiliary_models\`"
  fi

  if [[ -n "$diagnostics_text" ]]; then
    fallback_reason_text="$(format_review_fallback_reason "$diagnostics_text")"
    body="$body

Fallback reason:"
    while IFS= read -r item || [[ -n "$item" ]]; do
      [[ -n "$item" ]] || continue
      body="$body
$item"
    done <<< "$fallback_reason_text"
  fi

  if [[ -n "$normalizations_text" ]]; then
    body="$body

Output normalization:"
    while IFS= read -r item || [[ -n "$item" ]]; do
      [[ -n "$item" ]] || continue
      body="$body
- $item"
    done <<< "$normalizations_text"
  fi

  printf '%s' "$body"
}

parse_claude_stream_review() {
  local stream_file="$1"
  local review_file="$2"
  local model_file="$3"
  local auxiliary_models_file="$4"

  python3 - "$stream_file" "$review_file" "$model_file" "$auxiliary_models_file" <<'PY'
import json
import re
import sys

stream_file, review_file, model_file, auxiliary_models_file = sys.argv[1:5]
result = ""
assistant_text = []
response_model = ""
used_models = []

with open(stream_file, "r", encoding="utf-8") as fh:
    for line_number, raw_line in enumerate(fh, 1):
        if not raw_line.strip():
            continue
        try:
            data = json.loads(raw_line)
        except json.JSONDecodeError as error:
            raise ValueError(f"invalid Claude stream event on line {line_number}: {error}") from error

        if data.get("type") == "assistant" and data.get("parent_tool_use_id") is None:
            message = data.get("message") or {}
            model = message.get("model") or ""
            model = re.sub(r"\[[^\]]+\]$", "", model)
            if model and model != "<synthetic>" and not data.get("isApiErrorMessage"):
                response_model = model
            current_text = []
            for block in message.get("content") or []:
                if isinstance(block, dict) and block.get("type") == "text":
                    text = block.get("text")
                    if isinstance(text, str) and text:
                        current_text.append(text)
            if current_text:
                assistant_text = current_text

        if data.get("type") == "result":
            candidate = data.get("result")
            if isinstance(candidate, str) and candidate:
                result = candidate
            model_usage = data.get("modelUsage") or {}
            if isinstance(model_usage, dict):
                for model in model_usage:
                    normalized = re.sub(r"\[[^\]]+\]$", "", model)
                    if normalized and normalized not in used_models:
                        used_models.append(normalized)

if not result:
    result = "\n".join(assistant_text)

auxiliary_models = [model for model in used_models if model != response_model]

with open(review_file, "w", encoding="utf-8") as fh:
    fh.write(result)
with open(model_file, "w", encoding="utf-8") as fh:
    fh.write(response_model)
with open(auxiliary_models_file, "w", encoding="utf-8") as fh:
    fh.write(", ".join(auxiliary_models))
PY
}

parse_agy_stream_review() {
  local jsonl_file="$1"
  local review_file="$2"

  python3 - "$jsonl_file" "$review_file" <<'PY' 2>/dev/null
import json
import sys

jsonl_file, review_file = sys.argv[1:3]
result = None
with open(jsonl_file, "r", encoding="utf-8") as fh:
    for raw in fh:
        raw = raw.strip()
        if not raw:
            continue
        event = json.loads(raw)
        if event.get("event") == "result":
            result = event.get("result") or {}

if not result or result.get("status") != "SUCCESS":
    raise SystemExit(1)

response = result.get("response") or ""
if not isinstance(response, str) or not response.strip():
    raise SystemExit(1)

with open(review_file, "w", encoding="utf-8") as fh:
    fh.write(response)
PY
}

read_codex_default_model() {
  local config_file="${CODEX_HOME:-$HOME/.codex}/config.toml"

  [[ -f "$config_file" ]] || return 1
  awk -F= '
    /^[[:space:]]*model[[:space:]]*=/ {
      value=$2
      sub(/^[[:space:]]*/, "", value)
      sub(/[[:space:]]*$/, "", value)
      gsub(/^"|"$/, "", value)
      if (value != "") {
        print value
        exit 0
      }
    }
  ' "$config_file"
}

parse_codex_json_review() {
  local jsonl_file="$1"
  local review_file="$2"

  python3 - "$jsonl_file" "$review_file" <<'PY' 2>/dev/null
import json
import sys

jsonl_file, review_file = sys.argv[1:3]
messages = []
with open(jsonl_file, "r", encoding="utf-8") as fh:
    for raw in fh:
        raw = raw.strip()
        if not raw:
            continue
        try:
            event = json.loads(raw)
        except Exception:
            continue
        item = event.get("item") or {}
        if event.get("type") == "item.completed" and item.get("type") == "agent_message":
            text = item.get("text") or ""
            if text:
                messages.append(text)

with open(review_file, "w", encoding="utf-8") as fh:
    fh.write("\n".join(messages))
PY
}

parse_opencode_json_review() {
  local jsonl_file="$1"
  local review_file="$2"

  python3 - "$jsonl_file" "$review_file" <<'PY' 2>/dev/null
import json
import sys

jsonl_file, review_file = sys.argv[1:3]

# `opencode run --format json` emits newline-delimited events. Assistant prose
# arrives as {"type": "text", "part": {"id": ..., "text": ...}}. Observed
# behaviour is one complete event per part, but key by part id and keep the
# last value so a streamed part that is re-emitted as it grows is not
# concatenated with its own prefixes.
order = []
texts = {}
with open(jsonl_file, "r", encoding="utf-8") as fh:
    for raw in fh:
        raw = raw.strip()
        if not raw:
            continue
        try:
            event = json.loads(raw)
        except Exception:
            continue
        if event.get("type") != "text":
            continue
        part = event.get("part") or {}
        text = part.get("text") or ""
        if not text:
            continue
        key = part.get("id") or len(order)
        if key not in texts:
            order.append(key)
        texts[key] = text

with open(review_file, "w", encoding="utf-8") as fh:
    fh.write("\n".join(texts[key] for key in order))
PY
}

run_opencode_review() {
  local model="$1"
  local prompt="$2"
  local diff="$3"
  local repo_root="$4"
  local actual_model_file="$5"
  local detail_file="$6"
  local try_args=()
  local tmp_json tmp_review tmp_error try_exit

  command -v opencode &>/dev/null || return 127

  # OpenCode reports no model id in its run events, so only a model that was
  # requested explicitly can be echoed back; "default" leaves the file empty
  # and the caller falls back to the configured name.
  if [[ "$model" != "default" ]]; then
    try_args=(-m "$model")
    printf '%s' "$model" > "$actual_model_file"
  fi

  tmp_json="$(mktemp)"
  tmp_review="$(mktemp)"
  tmp_error="$(mktemp)"

  # --agent plan is OpenCode's built-in read-only agent. The default `build`
  # agent is configured with "*": "allow", which would let an unattended review
  # edit the repo it is reviewing; this mirrors codex's --sandbox read-only.
  printf '%s' "$diff" \
    | opencode run --format json --agent plan --dir "$repo_root" "${try_args[@]}" "$prompt" \
      > "$tmp_json" 2>"$tmp_error"
  try_exit=$?

  if [[ $try_exit -eq 0 ]] \
    && parse_opencode_json_review "$tmp_json" "$tmp_review" \
    && [[ -s "$tmp_review" ]]; then
    cat "$tmp_review" 2>/dev/null
  else
    { cat "$tmp_error" 2>/dev/null; cat "$tmp_json" 2>/dev/null; } > "$detail_file"
    [[ $try_exit -eq 0 ]] && try_exit=65
  fi

  rm -f "$tmp_json" "$tmp_review" "$tmp_error"
  return "$try_exit"
}

run_opencode_go_api_review() {
  local model="$1"
  local prompt="$2"
  local diff="$3"
  local _repo_root="$4"
  local actual_model_file="$5"
  local detail_file="$6"
  local api_key="${OPENCODE_GO_API_KEY:-}"
  local prompt_file try_exit

  command -v python3 &>/dev/null || return 127
  [[ -f "$SCRIPT_DIR/opencode_go.py" ]] || return 127

  if [[ -z "$api_key" ]]; then
    if ! api_key="$(python3 "$SCRIPT_DIR/opencode_go.py" read-key "$OPENCODE_GO_ENV_FILE" 2>"$detail_file")"; then
      return "$REVIEW_EXIT_NONRETRYABLE"
    fi
  fi

  prompt_file="$(mktemp)"
  printf '%s\n\nReview this pull request diff:\n%s\n' "$prompt" "$diff" > "$prompt_file"
  printf '%s' "$model" > "$actual_model_file"
  OPENCODE_GO_API_KEY="$api_key" \
    python3 "$SCRIPT_DIR/opencode_go.py" review "$model" "$prompt_file" \
      2>"$detail_file"
  try_exit=$?
  rm -f "$prompt_file"
  return "$try_exit"
}

run_claude_review() {
  local model="$1"
  local prompt="$2"
  local diff="$3"
  local actual_model_file="$4"
  local detail_file="$5"
  local auxiliary_models_file="${6:-}"
  local try_args=()
  local tmp_stream tmp_review tmp_model tmp_auxiliary tmp_error try_output try_exit

  command -v claude &>/dev/null || return 127
  [[ "$model" != "default" ]] && try_args=(--model "$model")

  tmp_stream="$(mktemp)"
  tmp_review="$(mktemp)"
  tmp_model="$(mktemp)"
  tmp_auxiliary="$(mktemp)"
  tmp_error="$(mktemp)"

  try_output=$(printf '%s' "$diff" | claude -p "${try_args[@]}" --output-format stream-json --verbose "$prompt" > "$tmp_stream" 2>"$tmp_error")
  try_exit=$?

  if [[ $try_exit -eq 0 ]] \
    && parse_claude_stream_review "$tmp_stream" "$tmp_review" "$tmp_model" "$tmp_auxiliary" 2>>"$tmp_error"; then
    try_output="$(cat "$tmp_review" 2>/dev/null)"
    if [[ -s "$tmp_model" ]]; then
      cat "$tmp_model" > "$actual_model_file"
    fi
    if [[ -n "$auxiliary_models_file" && -s "$tmp_auxiliary" ]]; then
      cat "$tmp_auxiliary" > "$auxiliary_models_file"
    fi
  else
    { cat "$tmp_error" 2>/dev/null; cat "$tmp_stream" 2>/dev/null; } > "$detail_file"
    [[ $try_exit -eq 0 ]] && try_exit=65
    try_output=""
  fi

  printf '%s' "$try_output"
  rm -f "$tmp_stream" "$tmp_review" "$tmp_model" "$tmp_auxiliary" "$tmp_error"
  return "$try_exit"
}

run_codex_review() {
  local model="$1"
  local prompt="$2"
  local diff="$3"
  local repo_root="$4"
  local actual_model_file="$5"
  local detail_file="$6"
  local try_args=()
  local tmp_json tmp_review tmp_error
  local try_exit

  command -v codex &>/dev/null || return 127
  [[ "$model" != "default" ]] && try_args=(-m "$model")

  if [[ "$model" == "default" ]]; then
    read_codex_default_model > "$actual_model_file" || printf '%s' "$model" > "$actual_model_file"
  else
    printf '%s' "$model" > "$actual_model_file"
  fi

  tmp_json="$(mktemp)"
  tmp_review="$(mktemp)"
  tmp_error="$(mktemp)"
  printf '%s' "$diff" \
    | codex exec -C "$repo_root" --json --sandbox read-only --skip-git-repo-check --ephemeral --color never "${try_args[@]}" "$prompt" > "$tmp_json" 2>"$tmp_error"
  try_exit=$?

  if [[ $try_exit -eq 0 ]] && parse_codex_json_review "$tmp_json" "$tmp_review"; then
    cat "$tmp_review" 2>/dev/null
  elif [[ $try_exit -eq 0 ]]; then
    { cat "$tmp_error" 2>/dev/null; cat "$tmp_json" 2>/dev/null; } > "$detail_file"
    try_exit=65
  else
    { cat "$tmp_error" 2>/dev/null; cat "$tmp_json" 2>/dev/null; } > "$detail_file"
  fi

  rm -f "$tmp_json" "$tmp_review" "$tmp_error"
  return "$try_exit"
}

run_agy_review() {
  local model="$1"
  local prompt="$2"
  local diff="$3"
  local repo_root="$4"
  local actual_model_file="$5"
  local detail_file="$6"
  local try_args=()
  local tmp_prompt tmp_input tmp_json tmp_review tmp_error try_output try_exit

  command -v agy &>/dev/null || return 127
  if [[ "$model" != "default" ]]; then
    try_args=(--model "$model")
    printf '%s' "$model" > "$actual_model_file"
  fi

  tmp_prompt="$(mktemp)"
  tmp_input="$(mktemp)"
  tmp_json="$(mktemp)"
  tmp_review="$(mktemp)"
  tmp_error="$(mktemp)"

  {
    printf '%s\n\n<pull_request_diff>\n' "$prompt"
    printf '%s\n' "$diff"
    printf '</pull_request_diff>\n'
  } > "$tmp_prompt"

  if ! python3 - "$tmp_prompt" "$tmp_input" <<'PY' 2>"$tmp_error"
import json
import sys

prompt_file, input_file = sys.argv[1:3]
with open(prompt_file, "r", encoding="utf-8") as fh:
    prompt = fh.read()
event = {"event": "user", "message": {"content": prompt}}
with open(input_file, "w", encoding="utf-8") as fh:
    fh.write(json.dumps(event, ensure_ascii=False) + "\n")
PY
  then
    cat "$tmp_error" > "$detail_file" 2>/dev/null || true
    rm -f "$tmp_prompt" "$tmp_input" "$tmp_json" "$tmp_review" "$tmp_error"
    return "$REVIEW_EXIT_NONRETRYABLE"
  fi

  (
    cd "$repo_root" || exit 1
    agy \
      --input-format stream-json \
      --output-format stream-json \
      --mode plan \
      --sandbox \
      "${try_args[@]}" \
      < "$tmp_input" > "$tmp_json" 2> "$tmp_error"
  )
  try_exit=$?

  if [[ $try_exit -eq 0 ]] && parse_agy_stream_review "$tmp_json" "$tmp_review"; then
    try_output="$(cat "$tmp_review" 2>/dev/null)"
  else
    { cat "$tmp_error" 2>/dev/null; cat "$tmp_json" 2>/dev/null; } > "$detail_file"
    [[ $try_exit -eq 0 ]] && try_exit=65
    try_output=""
  fi

  printf '%s' "$try_output"
  rm -f "$tmp_prompt" "$tmp_input" "$tmp_json" "$tmp_review" "$tmp_error"
  return "$try_exit"
}

run_experimental_review() {
  local reviewer="$1"
  local detail_file="$2"
  command -v "$(reviewer_command "$reviewer")" &>/dev/null || return 127
  printf '%s reviewer support is experimental and is not enabled for unattended auto-merge yet.' "$(reviewer_display_name "$reviewer")" > "$detail_file"
  return 2
}

run_review_attempt() {
  local reviewer="$1"
  local model="$2"
  local prompt="$3"
  local diff="$4"
  local repo_root="$5"
  local actual_model_file="$6"
  local detail_file="$7"
  local auxiliary_models_file="${8:-}"

  case "$reviewer" in
    claude) run_claude_review "$model" "$prompt" "$diff" "$actual_model_file" "$detail_file" "$auxiliary_models_file" ;;
    codex) run_codex_review "$model" "$prompt" "$diff" "$repo_root" "$actual_model_file" "$detail_file" ;;
    agy) run_agy_review "$model" "$prompt" "$diff" "$repo_root" "$actual_model_file" "$detail_file" ;;
    opencode) run_opencode_review "$model" "$prompt" "$diff" "$repo_root" "$actual_model_file" "$detail_file" ;;
    opencode-go-api) run_opencode_go_api_review "$model" "$prompt" "$diff" "$repo_root" "$actual_model_file" "$detail_file" ;;
    cursor|ollama) run_experimental_review "$reviewer" "$detail_file" ;;
    *) return 64 ;;
  esac
}

review_pr() {
  local pr_number="$1"
  local pr_url="$2"
  local raw_diff diff repo_root prompt_file raw_prompt prompt
  local reviewers=()
  local models=()
  local attempts=()
  local diagnostics=()
  local normalizations=()
  local reviewer model review try_output try_exit verdict
  local reviewer_name reviewer_link footer actual_model actual_model_file detail_file
  local auxiliary_models auxiliary_models_file
  local raw_detail detail normalized_review_file normalization_file normalization_detail
  local diagnostics_body

  raw_diff=$(gh pr diff "$pr_number" 2>/dev/null)
  if [[ -z "$raw_diff" ]]; then
    write_pr_body "$pr_number" "**Auto-review failed**: could not retrieve PR diff."
    notify_error "Failed to get PR diff — PR #$pr_number left open" "$pr_url"
    return 1
  fi
  if ! diff="$(printf '%s' "$raw_diff" | normalize_review_input)"; then
    write_pr_body "$pr_number" "**Auto-review failed**: could not prepare the PR diff as UTF-8 text."
    notify_error "Failed to prepare review input — PR #$pr_number left open" "$pr_url"
    return 1
  fi

  repo_root=$(git rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$DOTFILES_REPO_DIR")
  prompt_file="$repo_root/.github/review-prompt.md"
  if [[ ! -f "$prompt_file" ]]; then
    write_pr_body "$pr_number" "**Auto-review skipped**: review prompt file not found."
    notify_error "review-prompt.md missing — PR #$pr_number left open" "$pr_url"
    return 1
  fi

  raw_prompt=$(cat "$prompt_file")
  if ! prompt="$(printf '%s' "$raw_prompt" | normalize_review_input)"; then
    write_pr_body "$pr_number" "**Auto-review failed**: could not prepare the review policy as UTF-8 text."
    notify_error "Failed to prepare review policy — PR #$pr_number left open" "$pr_url"
    return 1
  fi

  while IFS= read -r reviewer; do
    [[ -n "$reviewer" ]] && reviewers+=("$reviewer")
  done < <(configured_reviewers)

  if [[ "${#reviewers[@]}" -eq 0 ]]; then
    reviewers=("claude")
  fi

  for reviewer in "${reviewers[@]}"; do
    models=()
    while IFS= read -r model; do
      [[ -n "$model" ]] && models+=("$model")
    done < <(models_for_reviewer "$reviewer" "$prompt_file")
    [[ "${#models[@]}" -eq 0 ]] && models=("default")

    for model in "${models[@]}"; do
      reviewer_name="$(reviewer_display_name "$reviewer")"
      actual_model_file="$(mktemp)"
      detail_file="$(mktemp)"
      auxiliary_models_file="$(mktemp)"
      echo "  ↳ reviewing with $reviewer_name (model: $model)..." >&2
      try_output="$(run_review_attempt "$reviewer" "$model" "$prompt" "$diff" "$repo_root" "$actual_model_file" "$detail_file" "$auxiliary_models_file")"
      try_exit=$?

      if [[ $try_exit -eq 0 && -n "$try_output" ]]; then
        normalized_review_file="$(mktemp)"
        normalization_file="$(mktemp)"
        printf '%s' "$try_output" > "$normalized_review_file.raw"

        if ! normalize_review_output "$normalized_review_file.raw" "$normalized_review_file" "$normalization_file"; then
          normalization_detail="$(cat "$normalization_file" 2>/dev/null)"
          [[ -n "$normalization_detail" ]] || normalization_detail="invalid verdict format"
          attempts+=("$reviewer_name ($model): invalid review output ($normalization_detail)")
          diagnostics+=("$reviewer_name (\`$model\`): invalid review output, $normalization_detail")
          rm -f "$actual_model_file" "$detail_file" "$auxiliary_models_file" "$normalized_review_file" "$normalized_review_file.raw" "$normalization_file"
          echo "  ↳ $reviewer_name ($model) returned invalid review output, trying next reviewer/model..." >&2
          continue
        fi

        review="$(cat "$normalized_review_file" 2>/dev/null)"
        normalization_detail="$(cat "$normalization_file" 2>/dev/null)"
        if [[ -n "$normalization_detail" ]]; then
          normalizations+=("$reviewer_name (\`$model\`): $normalization_detail")
        fi
        rm -f "$normalized_review_file" "$normalized_review_file.raw" "$normalization_file"

        verdict="$(printf '%s\n' "$review" | first_review_line)"
        reviewer_link="$(reviewer_url "$reviewer")"
        actual_model="$(cat "$actual_model_file" 2>/dev/null)"
        auxiliary_models="$(cat "$auxiliary_models_file" 2>/dev/null)"
        [[ -n "$actual_model" ]] || actual_model="$model"
        if [[ "$actual_model" != "$model" ]]; then
          footer="> Reviewed by **$reviewer_name** (model: \`$actual_model\`, configured: \`$model\`)"
        else
          footer="> Reviewed by **$reviewer_name** (model: \`$model\`)"
        fi
        [[ -n "$reviewer_link" ]] && footer="$footer via [$reviewer_name]($reviewer_link)"
        if [[ -n "$auxiliary_models" ]]; then
          footer="$footer
> Auxiliary models: \`$auxiliary_models\`"
        fi
        rm -f "$actual_model_file" "$detail_file" "$auxiliary_models_file"

        write_pr_body "$pr_number" "$review

---
$footer"

        if [[ "${#diagnostics[@]}" -gt 0 || "${#normalizations[@]}" -gt 0 ]]; then
          diagnostics_body="$(build_review_diagnostics_body \
            "$reviewer_name" \
            "$model" \
            "$actual_model" \
            "$(lines_from_array "${diagnostics[@]}")" \
            "$(lines_from_array "${normalizations[@]}")" \
            "$auxiliary_models")"
          upsert_review_diagnostics_comment "$pr_number" "$diagnostics_body"
        else
          delete_review_diagnostics_comment "$pr_number"
        fi

        if [[ "$verdict" == "APPROVED" ]]; then
          return 0
        fi

        notify_error "PR #$pr_number flagged by $reviewer_name review — needs manual check" "$pr_url"
        return 1
      fi

      raw_detail="$(cat "$detail_file" 2>/dev/null)"
      detail="$(printf '%s' "$raw_detail" | sanitize_review_detail)"
      [[ -n "$detail" ]] || detail="no diagnostic detail"

      if [[ $try_exit -eq 127 ]]; then
        attempts+=("$reviewer_name ($model): CLI not found")
        diagnostics+=("$reviewer_name (\`$model\`): CLI not found")
      elif [[ -z "$try_output" ]]; then
        attempts+=("$reviewer_name ($model): empty response, exit=$try_exit, $detail")
        diagnostics+=("$reviewer_name (\`$model\`): failed, exit=$try_exit, $detail")
      else
        attempts+=("$reviewer_name ($model): $(printf '%s\n' "$try_output" | first_review_line), exit=$try_exit, $detail")
        diagnostics+=("$reviewer_name (\`$model\`): failed, exit=$try_exit, $detail")
      fi
      rm -f "$actual_model_file" "$detail_file" "$auxiliary_models_file"
      if [[ $try_exit -eq $REVIEW_EXIT_NONRETRYABLE || $try_exit -eq 127 ]]; then
        echo "  ↳ $reviewer_name is unavailable for this run (exit=$try_exit), skipping its remaining models..." >&2
        break
      fi
      echo "  ↳ $reviewer_name ($model) failed (exit=$try_exit), trying next reviewer/model..." >&2
    done
  done

  local failure_body="**Auto-review failed**: all configured reviewers failed or returned no usable review.

Attempted reviewers:"
  for try_output in "${attempts[@]}"; do
    failure_body="$failure_body
- $try_output"
  done
  failure_body="$failure_body

Please review this backup manually before merging."

  write_pr_body "$pr_number" "$failure_body"
  if [[ "${#diagnostics[@]}" -gt 0 || "${#normalizations[@]}" -gt 0 ]]; then
    diagnostics_body="$(build_review_diagnostics_body \
      "none" \
      "none" \
      "none" \
      "$(lines_from_array "${diagnostics[@]}")" \
      "$(lines_from_array "${normalizations[@]}")")"
    upsert_review_diagnostics_comment "$pr_number" "$diagnostics_body"
  fi
  notify_error "AI review failed — PR #$pr_number left open" "$pr_url"
  return 1
}

if [[ "${DOTFILES_AUTOBACKUP_SOURCE_ONLY:-}" == true ]]; then
  return 0 2>/dev/null || exit 0
fi

# ── Test mode (--test) ───────────────────────────────────────────
# Stays on current dev branch. Pushes, creates PR if needed, runs review.
# No backup, no merge, no branch switching.
if [[ "$TEST_MODE" == true ]]; then
  cd "$DOTFILES_REPO_DIR" || exit 1
  ORIGINAL_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || git rev-parse HEAD)
  CURRENT_BRANCH="$ORIGINAL_BRANCH"

  # Push current branch
  if ! git push -u origin "$CURRENT_BRANCH" > /dev/null 2>&1; then
    echo "✗ Failed to push $CURRENT_BRANCH to origin"
    git checkout "$ORIGINAL_BRANCH" > /dev/null 2>&1
    exit 1
  fi

  # Find or create PR
  PR_NUMBER=$(gh pr list --head "$CURRENT_BRANCH" --base main --state open --json number --jq '.[0].number' 2>/dev/null)

  if [[ -z "$PR_NUMBER" ]]; then
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M")
    PR_NUMBER=$(gh pr create \
      --base main \
      --head "$CURRENT_BRANCH" \
      --title "Test: $CURRENT_BRANCH ($TIMESTAMP)" \
      --body "Test PR for reviewing changes on \`$CURRENT_BRANCH\`." \
      2>/dev/null | grep -oE '[0-9]+$')

    if [[ -n "$PR_NUMBER" ]]; then
      echo "✓ Created PR #$PR_NUMBER"
    else
      echo "✗ Failed to create PR for $CURRENT_BRANCH → main"
      git checkout "$ORIGINAL_BRANCH" > /dev/null 2>&1
      exit 1
    fi
  fi

  PR_URL="$(github_url "pull/$PR_NUMBER")"

  echo "Reviewing PR #$PR_NUMBER ($CURRENT_BRANCH)..."

  if [[ "$NO_REVIEW" != true ]]; then
    if review_pr "$PR_NUMBER" "$PR_URL"; then
      echo "✓ Review passed — PR #$PR_NUMBER approved"
    else
      echo "✗ Review flagged issues — check PR body"
    fi
  else
    echo "✓ PR #$PR_NUMBER created (review skipped)"
  fi

  # Always restore original branch
  git checkout "$ORIGINAL_BRANCH" > /dev/null 2>&1
  exit 0
fi

# ── Device branch detection ───────────────────────────────────────
get_device_branch() {
  local model serial_suffix username

  # Model name: "MacBook Pro" → "MacBookPro"
  model=$(system_profiler SPHardwareDataType 2>/dev/null \
    | awk -F': ' '/Model Name/ {print $2}' \
    | tr -d ' ')

  # Fallback: hw.model with comma replaced → "Mac16-7"
  if [[ -z "$model" ]]; then
    model=$(sysctl -n hw.model 2>/dev/null | tr ',' '-')
  fi

  # Last 2 chars of serial number
  local serial
  serial=$(system_profiler SPHardwareDataType 2>/dev/null \
    | awk '/Serial Number/ {print $NF}')
  serial_suffix="${serial: -2}"

  # Fallback: short hostname
  if [[ -z "$serial_suffix" ]]; then
    serial_suffix=$(hostname -s | cut -c1-4)
  fi

  username=$(whoami)
  echo "device/${model}-${serial_suffix}/${username}"
}

cd "$DOTFILES_REPO_DIR" || exit 1

# ── Lockfile (prevent concurrent runs) ────────────────────────────
LOCKFILE="$DOTFILES_AUTOBACKUP_LOCKFILE"
if [[ -f "$LOCKFILE" ]]; then
  LOCK_PID=$(cat "$LOCKFILE" 2>/dev/null)
  if kill -0 "$LOCK_PID" 2>/dev/null; then
    echo "✗ Another auto-commit is running (PID $LOCK_PID)"
    exit 0
  fi
fi
echo $$ > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

# ── Resolve device branch ────────────────────────────────────────
DEVICE_BRANCH=$(get_device_branch)

# ── Save current git state ───────────────────────────────────────
ORIGINAL_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || git rev-parse HEAD)
NEEDS_RESTORE=false
STASHED=false

if [[ "$ORIGINAL_BRANCH" != "$DEVICE_BRANCH" ]]; then
  NEEDS_RESTORE=true

  # Stash any uncommitted work, including new files from in-progress feature work.
  if ! git diff --quiet || ! git diff --cached --quiet; then
    git stash push --include-untracked -m "auto-backup-temp" > /dev/null 2>&1
    STASHED=true
  elif [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
    git stash push --include-untracked -m "auto-backup-temp" > /dev/null 2>&1
    STASHED=true
  fi

  # Fetch remote refs so we can detect remote-only branches
  git fetch origin > /dev/null 2>&1 || true

  # Switch to device branch (create if needed)
  if git show-ref --verify --quiet "refs/heads/$DEVICE_BRANCH"; then
    # Branch exists locally
    git checkout "$DEVICE_BRANCH" > /dev/null 2>&1
  elif git show-ref --verify --quiet "refs/remotes/origin/$DEVICE_BRANCH"; then
    # Branch exists on remote but not locally — track it
    git checkout -b "$DEVICE_BRANCH" "origin/$DEVICE_BRANCH" > /dev/null 2>&1
  else
    # New device: branch from main
    git checkout -b "$DEVICE_BRANCH" origin/main > /dev/null 2>&1
  fi
fi

# ── Sync with main (pick up new scripts/features) ────────────────
# Rebase on main so the device branch has latest repo changes.
# Safe because backup.sh runs AFTER and overwrites configs with this device's own files.
# After a squash merge to main, the device branch diverges (same content, different
# commits), so rebase will conflict. In that case, reset to main — backup.sh will
# re-capture everything from the current system.
# Skip with --no-rebase for testing feature branches.
REBASED=false
if [[ "$NO_REBASE" != true ]]; then
  if git fetch origin main > /dev/null 2>&1; then
    if ! git rebase origin/main > /dev/null 2>&1; then
      git rebase --abort > /dev/null 2>&1
      # Rebase failed (likely after squash merge divergence) — reset to main
      git reset --hard origin/main > /dev/null 2>&1
      REBASED=true
    else
      REBASED=true
    fi
  fi
fi

# ── Run backup ───────────────────────────────────────────────────
# backup.sh copies from the system into the repo, overwriting any
# config files the rebase brought in with this device's own configs
./backup.sh > /tmp/dotfiles-backup.log 2>&1

# ── Stage and check for changes ──────────────────────────────────
git add -A

TIMESTAMP=$(date "+%Y-%m-%d %H:%M")

if git diff --cached --quiet; then
  notify_success "No changes detected"
  echo "✓ No changes detected"
  # Restore original branch if needed
  if [[ "$NEEDS_RESTORE" == true ]]; then
    git checkout "$ORIGINAL_BRANCH" > /dev/null 2>&1
    [[ "$STASHED" == true ]] && git stash pop > /dev/null 2>&1
  fi
  exit 0
fi

# ── Build summary (unchanged category detection) ─────────────────
CHANGED_FILES=$(git diff --cached --name-only)
FILE_COUNT=$(echo "$CHANGED_FILES" | wc -l | xargs)

SUMMARY=""
echo "$CHANGED_FILES" | grep -q "^apps/Brewfile" && SUMMARY="$SUMMARY, Brewfile"
echo "$CHANGED_FILES" | grep -q "^cli/shell/" && SUMMARY="$SUMMARY, Shell"
echo "$CHANGED_FILES" | grep -q "^cli/git/" && SUMMARY="$SUMMARY, Git"
echo "$CHANGED_FILES" | grep -q "^apps/terminal/" && SUMMARY="$SUMMARY, Ghostty"
echo "$CHANGED_FILES" | grep -q "^apps/editors/cursor/" && SUMMARY="$SUMMARY, Cursor"
echo "$CHANGED_FILES" | grep -q "^apps/editors/vscode/" && SUMMARY="$SUMMARY, VS Code"
echo "$CHANGED_FILES" | grep -q "^apps/editors/zed/" && SUMMARY="$SUMMARY, Zed"
echo "$CHANGED_FILES" | grep -q "^apps/ai-tools/claude/" && SUMMARY="$SUMMARY, Claude"
echo "$CHANGED_FILES" | grep -q "^apps/ai-tools/codex/" && SUMMARY="$SUMMARY, Codex"
echo "$CHANGED_FILES" | grep -q "^apps/ai-tools/antigravity/" && SUMMARY="$SUMMARY, Antigravity"
echo "$CHANGED_FILES" | grep -q "^apps/ai-tools/opencode/" && SUMMARY="$SUMMARY, OpenCode"
echo "$CHANGED_FILES" | grep -q "^apps/ai-tools/agents/" && SUMMARY="$SUMMARY, Agent Skills"
echo "$CHANGED_FILES" | grep -q "^apps/ai-tools/t3code/" && SUMMARY="$SUMMARY, T3 Code"
echo "$CHANGED_FILES" | grep -q "^cli/ssh/" && SUMMARY="$SUMMARY, SSH"
echo "$CHANGED_FILES" | grep -q "^cli/misc/" && SUMMARY="$SUMMARY, CLI misc"
echo "$CHANGED_FILES" | grep -q "^languages/node/" && SUMMARY="$SUMMARY, Node"
echo "$CHANGED_FILES" | grep -q "^languages/python/" && SUMMARY="$SUMMARY, Python"
echo "$CHANGED_FILES" | grep -q "^fonts/" && SUMMARY="$SUMMARY, Fonts"
echo "$CHANGED_FILES" | grep -q "^apps/multiviewer/" && SUMMARY="$SUMMARY, MultiViewer"
echo "$CHANGED_FILES" | grep -q "^macos/" && SUMMARY="$SUMMARY, macOS"
echo "$CHANGED_FILES" | grep -q "^history/" && SUMMARY="$SUMMARY, History"
SUMMARY="${SUMMARY#, }"

# ── Commit ───────────────────────────────────────────────────────
git commit -m "Auto-backup: $TIMESTAMP" > /dev/null 2>&1

# ── Push to device branch ────────────────────────────────────────
PUSHED=""
if git push -f -u origin "$DEVICE_BRANCH" 2>/dev/null; then
  PUSHED=" & pushed"
else
  notify_error "Push to $DEVICE_BRANCH failed"
fi

# ── Restore original branch ──────────────────────────────────────
if [[ "$NEEDS_RESTORE" == true ]]; then
  git checkout "$ORIGINAL_BRANCH" > /dev/null 2>&1
  if [[ "$STASHED" == true ]]; then
    if ! git stash pop > /dev/null 2>&1; then
      notify_error "Failed to restore stashed changes"
    fi
  fi
fi

# ── Build output message ─────────────────────────────────────────
OUTPUT="✓ $FILE_COUNT files$PUSHED"
[[ -n "$SUMMARY" ]] && OUTPUT="$OUTPUT ($SUMMARY)"
OUTPUT="$OUTPUT to $DEVICE_BRANCH"
[[ "$REBASED" == true ]] && OUTPUT="$OUTPUT | rebased"

# ── PR flow (--main-pc or --pr-only) ─────────────────────────────
if [[ ("$MAIN_PC" == true || "$PR_ONLY" == true) && -n "$PUSHED" ]]; then
  # Ensure gh is available
  if ! command -v gh &>/dev/null; then
    notify_error "gh CLI not found — cannot create PR"
    exit 0
  fi

  # Switch to device branch for PR operations
  if [[ "$NEEDS_RESTORE" == true ]]; then
    git checkout "$DEVICE_BRANCH" > /dev/null 2>&1
  fi

  # Check if there's anything new vs main
  git fetch origin main > /dev/null 2>&1
  if git diff "origin/main...$DEVICE_BRANCH" --quiet 2>/dev/null; then
    echo "✓ Device branch already in sync with main"
    if [[ "$NEEDS_RESTORE" == true ]]; then
      git checkout "$ORIGINAL_BRANCH" > /dev/null 2>&1
    fi
    exit 0
  fi

  # Force push (rebase already done before backup)
  if ! git push -f origin "$DEVICE_BRANCH" > /dev/null 2>&1; then
    notify_error "Push to $DEVICE_BRANCH failed before PR"
    if [[ "$NEEDS_RESTORE" == true ]]; then
      git checkout "$ORIGINAL_BRANCH" > /dev/null 2>&1
    fi
    exit 0
  fi

  # Check for existing open PR
  PR_NUMBER=$(gh pr list --head "$DEVICE_BRANCH" --base main --state open --json number --jq '.[0].number' 2>/dev/null)

  if [[ -z "$PR_NUMBER" ]]; then
    # Create new PR
    PR_NUMBER=$(gh pr create \
      --base main \
      --head "$DEVICE_BRANCH" \
      --title "Auto-backup ($DEVICE_BRANCH): $TIMESTAMP" \
      --body "Automated dotfiles backup from $(scutil --get ComputerName 2>/dev/null || hostname)." \
      2>/dev/null | grep -oE '[0-9]+$')

    if [[ -z "$PR_NUMBER" ]]; then
      notify_error "Failed to create PR to main"
      if [[ "$NEEDS_RESTORE" == true ]]; then
        git checkout "$ORIGINAL_BRANCH" > /dev/null 2>&1
      fi
      exit 0
    fi
  fi

  PR_URL="$(github_url "pull/$PR_NUMBER")"

  # Review (unless --no-review)
  REVIEW_PASSED=true
  if [[ "$NO_REVIEW" != true ]]; then
    if ! review_pr "$PR_NUMBER" "$PR_URL"; then
      REVIEW_PASSED=false
    fi
  fi

  if [[ "$PR_ONLY" == true ]]; then
    # --pr-only: never merge, just report
    OUTPUT="$OUTPUT | PR #$PR_NUMBER"
    [[ "$REVIEW_PASSED" == true ]] && OUTPUT="$OUTPUT (reviewed)" || OUTPUT="$OUTPUT (review flagged)"
    notify_success "$OUTPUT" "$PR_URL"
    echo "$OUTPUT"
  elif [[ "$REVIEW_PASSED" == true ]]; then
    # --main-pc: merge only if review passed
    if gh pr merge "$PR_NUMBER" --squash > /dev/null 2>&1; then
      # Sync device branch to main after squash merge
      git fetch origin main > /dev/null 2>&1
      git reset --hard origin/main > /dev/null 2>&1
      git push -f origin "$DEVICE_BRANCH" > /dev/null 2>&1

      OUTPUT="$OUTPUT | merged to main (#$PR_NUMBER)"
      notify_success "$OUTPUT" "$PR_URL"
      echo "$OUTPUT"
    else
      notify_error "PR #$PR_NUMBER merge failed — merge manually" "$PR_URL"
      echo "$OUTPUT"
    fi
  else
    # --main-pc but review failed: leave PR open
    OUTPUT="$OUTPUT | PR #$PR_NUMBER awaiting review"
    echo "$OUTPUT"
  fi

  # Restore original branch
  if [[ "$NEEDS_RESTORE" == true ]]; then
    git checkout "$ORIGINAL_BRANCH" > /dev/null 2>&1
  fi
  exit 0
fi

# ── Output (no PR/merge) ────────────────────────────────────────
if [[ -n "$PUSHED" ]]; then
  BRANCH_URL="$(github_url "tree/$DEVICE_BRANCH")"
  notify_success "$OUTPUT" "$BRANCH_URL"
fi
echo "$OUTPUT"

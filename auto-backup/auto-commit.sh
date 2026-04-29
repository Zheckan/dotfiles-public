#!/usr/bin/env bash
# Auto-commit script — called by LaunchAgent or Apple Shortcut
# Sets up PATH for non-interactive environments (Shortcuts, launchd)

# Load Homebrew and user PATH
eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null)" || true
export PATH="$HOME/.nvm/versions/node/$(ls "$HOME/.nvm/versions/node/" 2>/dev/null | tail -1)/bin:$PATH" 2>/dev/null || true
export PATH="/usr/local/bin:$HOME/.local/bin:$PATH"

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

is_allowed_config_key() {
  case "$1" in
    DOTFILES_AUTOBACKUP_MODE|DOTFILES_AUTOBACKUP_REBASE|DOTFILES_AUTOBACKUP_REVIEW|DOTFILES_REVIEWERS|DOTFILES_REVIEW_CLAUDE_MODELS|DOTFILES_REVIEW_CODEX_MODELS|DOTFILES_REVIEW_GEMINI_MODELS|DOTFILES_REVIEW_OPENCODE_MODELS|DOTFILES_REVIEW_CURSOR_MODELS|DOTFILES_REVIEW_OLLAMA_MODELS)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

decode_config_value() {
  local raw_value="$1"
  local value

  raw_value="$(trim "$raw_value")"
  if [[ "$raw_value" =~ ^\"([^\"\\]|\\.)*\"([[:space:]]*#.*)?$ ]]; then
    value="${raw_value%%\"*}"
    value="${raw_value#\"}"
    value="${value%\"*}"
  elif [[ "$raw_value" =~ ^\'[^\']*\'([[:space:]]*#.*)?$ ]]; then
    value="${raw_value%%\'*}"
    value="${raw_value#\'}"
    value="${value%\'*}"
  else
    value="$(trim "${raw_value%%#*}")"
  fi

  printf '%s' "$value"
}

load_config_file() {
  local file="$1"
  local line trimmed key raw_value value
  local line_no=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$((line_no + 1))
    trimmed="$(trim "$line")"

    [[ -z "$trimmed" ]] && continue
    [[ "${trimmed:0:1}" == "#" ]] && continue

    if [[ "$trimmed" =~ ^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      raw_value="${BASH_REMATCH[2]}"

      is_allowed_config_key "$key" || config_error "$file:$line_no: unsupported key '$key'"
      value="$(decode_config_value "$raw_value")"
      printf -v "$key" '%s' "$value"
    else
      config_error "$file:$line_no: expected KEY=VALUE assignment"
    fi
  done < "$file"
}

# Tracked defaults plus optional local overrides.
if [[ ! -f "$SCRIPT_DIR/config.env" ]]; then
  config_error "missing auto-backup/config.env; run auto-backup/configure.sh or restore the tracked config"
fi
load_config_file "$SCRIPT_DIR/config.env"
if [[ -f "$SCRIPT_DIR/config.local.env" ]]; then
  load_config_file "$SCRIPT_DIR/config.local.env"
fi

DOTFILES_AUTOBACKUP_MODE="${DOTFILES_AUTOBACKUP_MODE:-}"
DOTFILES_AUTOBACKUP_REBASE="${DOTFILES_AUTOBACKUP_REBASE:-}"
DOTFILES_AUTOBACKUP_REVIEW="${DOTFILES_AUTOBACKUP_REVIEW:-}"
DOTFILES_REVIEWERS="${DOTFILES_REVIEWERS:-}"
DOTFILES_REVIEW_CLAUDE_MODELS="${DOTFILES_REVIEW_CLAUDE_MODELS:-}"
DOTFILES_REVIEW_CODEX_MODELS="${DOTFILES_REVIEW_CODEX_MODELS:-}"
DOTFILES_REVIEW_GEMINI_MODELS="${DOTFILES_REVIEW_GEMINI_MODELS:-}"

# ── Flags ─────────────────────────────────────────────────────────
# --main-pc    : Full flow — rebase, backup, review, PR, merge
# --pr-only    : Same as --main-pc but without merge
# --no-rebase  : Skip rebase on main (combinable with above)
# --no-review  : Skip AI review (combinable with above)
# --test       : Test mode — stay on current branch, push, create PR, review (no backup, no merge)
# --claude/--codex/--gemini/... : Reviewers to try, in flag order
MODE_FLAG=""
REBASE_FLAG=""
REVIEW_FLAG=""
REVIEWER_FLAGS=()
for arg in "$@"; do
  case "$arg" in
    --main-pc) MODE_FLAG="main-pc" ;;
    --pr-only) MODE_FLAG="pr-only" ;;
    --no-rebase) REBASE_FLAG="false" ;;
    --no-review) REVIEW_FLAG="false" ;;
    --test) MODE_FLAG="test" ;;
    --claude) REVIEWER_FLAGS+=("claude") ;;
    --codex) REVIEWER_FLAGS+=("codex") ;;
    --gemini) REVIEWER_FLAGS+=("gemini") ;;
    --opencode) REVIEWER_FLAGS+=("opencode") ;;
    --cursor) REVIEWER_FLAGS+=("cursor") ;;
    --ollama) REVIEWER_FLAGS+=("ollama") ;;
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
    claude|codex|gemini|opencode|cursor|ollama) ;;
    *) config_error "unknown reviewer '$reviewer' (allowed: claude, codex, gemini, opencode, cursor, ollama)" ;;
  esac
}

validate_reviewers_config() {
  local reviewer

  if [[ "${#REVIEWER_FLAGS[@]}" -gt 0 ]]; then
    for reviewer in "${REVIEWER_FLAGS[@]}"; do
      validate_reviewer_name "$reviewer"
    done
    return 0
  fi

  validate_csv_nonempty "DOTFILES_REVIEWERS" "$DOTFILES_REVIEWERS"
  while IFS= read -r reviewer; do
    validate_reviewer_name "$reviewer"
  done < <(split_csv_lines "$DOTFILES_REVIEWERS")
}

model_list_name_for_reviewer() {
  case "$1" in
    claude) printf 'DOTFILES_REVIEW_CLAUDE_MODELS' ;;
    codex) printf 'DOTFILES_REVIEW_CODEX_MODELS' ;;
    gemini) printf 'DOTFILES_REVIEW_GEMINI_MODELS' ;;
    opencode) printf 'DOTFILES_REVIEW_OPENCODE_MODELS' ;;
    cursor) printf 'DOTFILES_REVIEW_CURSOR_MODELS' ;;
    ollama) printf 'DOTFILES_REVIEW_OLLAMA_MODELS' ;;
  esac
}

model_list_value_for_reviewer() {
  case "$1" in
    claude) printf '%s' "${DOTFILES_REVIEW_CLAUDE_MODELS:-}" ;;
    codex) printf '%s' "${DOTFILES_REVIEW_CODEX_MODELS:-}" ;;
    gemini) printf '%s' "${DOTFILES_REVIEW_GEMINI_MODELS:-}" ;;
    opencode) printf '%s' "${DOTFILES_REVIEW_OPENCODE_MODELS:-}" ;;
    cursor) printf '%s' "${DOTFILES_REVIEW_CURSOR_MODELS:-}" ;;
    ollama) printf '%s' "${DOTFILES_REVIEW_OLLAMA_MODELS:-}" ;;
  esac
}

validate_selected_model_lists() {
  local reviewer name value

  if [[ "${#REVIEWER_FLAGS[@]}" -gt 0 ]]; then
    for reviewer in "${REVIEWER_FLAGS[@]}"; do
      name="$(model_list_name_for_reviewer "$reviewer")"
      value="$(model_list_value_for_reviewer "$reviewer")"
      [[ -z "$(trim "$value")" ]] || validate_csv_nonempty "$name" "$value"
    done
    return 0
  fi

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
  if command -v terminal-notifier &>/dev/null; then
    local args=(-title "Dotfiles Backup" -message "$msg" -sound Basso)
    [[ -n "$url" ]] && args+=(-open "$url")
    terminal-notifier "${args[@]}" > /dev/null 2>&1 || true
  else
    osascript -e "display notification \"$msg\" with title \"Dotfiles Backup\" sound name \"Basso\"" 2>/dev/null || true
  fi
  echo "✗ $msg" >&2
}

notify_success() {
  local msg="$1" url="${2:-}"
  if command -v terminal-notifier &>/dev/null; then
    local args=(-title "Dotfiles Backup" -message "$msg")
    [[ -n "$url" ]] && args+=(-open "$url")
    terminal-notifier "${args[@]}" > /dev/null 2>&1 || true
  else
    osascript -e "display notification \"$msg\" with title \"Dotfiles Backup\"" 2>/dev/null || true
  fi
}

# ── PR Review (AI reviewer adapters) ─────────────────────────────
# Reviews the PR diff before allowing merge. Returns 0 if approved, 1 otherwise.
reviewer_display_name() {
  case "$1" in
    claude) printf 'Claude' ;;
    codex) printf 'Codex' ;;
    gemini) printf 'Gemini' ;;
    opencode) printf 'OpenCode' ;;
    cursor) printf 'Cursor' ;;
    ollama) printf 'Ollama' ;;
    *) printf '%s' "$1" ;;
  esac
}

reviewer_url() {
  case "$1" in
    claude) printf 'https://claude.com/claude-code' ;;
    codex) printf 'https://developers.openai.com/codex' ;;
    gemini) printf 'https://github.com/google-gemini/gemini-cli' ;;
    opencode) printf 'https://opencode.ai' ;;
    cursor) printf 'https://cursor.com' ;;
    ollama) printf 'https://ollama.com' ;;
  esac
}

reviewer_command() {
  case "$1" in
    claude) printf 'claude' ;;
    codex) printf 'codex' ;;
    gemini) printf 'gemini' ;;
    opencode) printf 'opencode' ;;
    cursor) printf 'cursor' ;;
    ollama) printf 'ollama' ;;
  esac
}

configured_reviewers() {
  local reviewer

  if [[ "${#REVIEWER_FLAGS[@]}" -gt 0 ]]; then
    for reviewer in "${REVIEWER_FLAGS[@]}"; do
      printf '%s\n' "$reviewer"
    done
    return 0
  fi

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
    gemini) raw="${DOTFILES_REVIEW_GEMINI_MODELS:-}" ;;
    opencode) raw="${DOTFILES_REVIEW_OPENCODE_MODELS:-}" ;;
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

write_pr_body() {
  local pr_number="$1"
  local body="$2"
  local tmp_body

  tmp_body="$(mktemp)"
  printf '%s\n' "$body" > "$tmp_body"
  gh pr edit "$pr_number" --body-file "$tmp_body" > /dev/null 2>&1
  rm -f "$tmp_body"
}

parse_claude_json_review() {
  local json_file="$1"
  local review_file="$2"
  local model_file="$3"

  python3 - "$json_file" "$review_file" "$model_file" <<'PY' 2>/dev/null
import json
import re
import sys

json_file, review_file, model_file = sys.argv[1:4]
with open(json_file, "r", encoding="utf-8") as fh:
    data = json.load(fh)

result = data.get("result") or ""
model_usage = data.get("modelUsage") or {}
model = next(iter(model_usage), "")
model = re.sub(r"\[[^\]]+\]$", "", model)

with open(review_file, "w", encoding="utf-8") as fh:
    fh.write(result)
with open(model_file, "w", encoding="utf-8") as fh:
    fh.write(model)
PY
}

parse_gemini_json_review() {
  local json_file="$1"
  local review_file="$2"
  local model_file="$3"

  python3 - "$json_file" "$review_file" "$model_file" <<'PY' 2>/dev/null
import json
import sys

json_file, review_file, model_file = sys.argv[1:4]
with open(json_file, "r", encoding="utf-8") as fh:
    data = json.load(fh)

response = data.get("response") or ""
models = ((data.get("stats") or {}).get("models") or {})
model = ""
for name, stats in models.items():
    if "main" in ((stats or {}).get("roles") or {}):
        model = name
        break
if not model and models:
    model = next(iter(models))

with open(review_file, "w", encoding="utf-8") as fh:
    fh.write(response)
with open(model_file, "w", encoding="utf-8") as fh:
    fh.write(model)
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

run_claude_review() {
  local model="$1"
  local prompt="$2"
  local diff="$3"
  local actual_model_file="$4"
  local try_args=()
  local tmp_json tmp_review tmp_model try_output try_exit

  command -v claude &>/dev/null || return 127
  [[ "$model" != "default" ]] && try_args=(--model "$model")

  tmp_json="$(mktemp)"
  tmp_review="$(mktemp)"
  tmp_model="$(mktemp)"

  try_output=$(printf '%s' "$diff" | claude -p "${try_args[@]}" --output-format json "$prompt" > "$tmp_json" 2>/dev/null)
  try_exit=$?

  if [[ $try_exit -eq 0 ]] && parse_claude_json_review "$tmp_json" "$tmp_review" "$tmp_model"; then
    try_output="$(cat "$tmp_review" 2>/dev/null)"
    if [[ -s "$tmp_model" ]]; then
      cat "$tmp_model" > "$actual_model_file"
    fi
  else
    [[ $try_exit -eq 0 ]] && try_exit=65
    try_output=""
  fi

  printf '%s' "$try_output"
  rm -f "$tmp_json" "$tmp_review" "$tmp_model"
  return "$try_exit"
}

run_codex_review() {
  local model="$1"
  local prompt="$2"
  local diff="$3"
  local repo_root="$4"
  local actual_model_file="$5"
  local try_args=()
  local tmp_json tmp_review
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
  printf '%s' "$diff" \
    | codex exec -C "$repo_root" --json --sandbox read-only --skip-git-repo-check --ephemeral --color never "${try_args[@]}" "$prompt" > "$tmp_json" 2>/dev/null
  try_exit=$?

  if parse_codex_json_review "$tmp_json" "$tmp_review"; then
    cat "$tmp_review" 2>/dev/null
  elif [[ $try_exit -eq 0 ]]; then
    try_exit=65
  fi

  rm -f "$tmp_json" "$tmp_review"
  return "$try_exit"
}

run_gemini_review() {
  local model="$1"
  local prompt="$2"
  local diff="$3"
  local actual_model_file="$4"
  local try_args=()
  local tmp_json tmp_review tmp_model try_output try_exit

  command -v gemini &>/dev/null || return 127
  [[ "$model" != "default" ]] && try_args=(-m "$model")

  tmp_json="$(mktemp)"
  tmp_review="$(mktemp)"
  tmp_model="$(mktemp)"

  printf '%s' "$diff" | gemini "${try_args[@]}" -p "$prompt" --output-format json > "$tmp_json" 2>/dev/null
  try_exit=$?

  if [[ $try_exit -eq 0 ]] && parse_gemini_json_review "$tmp_json" "$tmp_review" "$tmp_model"; then
    try_output="$(cat "$tmp_review" 2>/dev/null)"
    if [[ -s "$tmp_model" ]]; then
      cat "$tmp_model" > "$actual_model_file"
    fi
  else
    [[ $try_exit -eq 0 ]] && try_exit=65
    try_output=""
  fi

  printf '%s' "$try_output"
  rm -f "$tmp_json" "$tmp_review" "$tmp_model"
  return "$try_exit"
}

run_experimental_review() {
  local reviewer="$1"
  command -v "$(reviewer_command "$reviewer")" &>/dev/null || return 127
  printf '%s reviewer support is experimental and is not enabled for unattended auto-merge yet.' "$(reviewer_display_name "$reviewer")"
  return 2
}

run_review_attempt() {
  local reviewer="$1"
  local model="$2"
  local prompt="$3"
  local diff="$4"
  local repo_root="$5"
  local actual_model_file="$6"

  case "$reviewer" in
    claude) run_claude_review "$model" "$prompt" "$diff" "$actual_model_file" ;;
    codex) run_codex_review "$model" "$prompt" "$diff" "$repo_root" "$actual_model_file" ;;
    gemini) run_gemini_review "$model" "$prompt" "$diff" "$actual_model_file" ;;
    opencode|cursor|ollama) run_experimental_review "$reviewer" ;;
    *) return 64 ;;
  esac
}

review_pr() {
  local pr_number="$1"
  local pr_url="$2"
  local diff repo_root prompt_file prompt
  local reviewers=()
  local models=()
  local attempts=()
  local reviewer model review try_output try_exit verdict
  local reviewer_name reviewer_link footer actual_model actual_model_file

  diff=$(gh pr diff "$pr_number" 2>/dev/null)
  if [[ -z "$diff" ]]; then
    write_pr_body "$pr_number" "**Auto-review failed**: could not retrieve PR diff."
    notify_error "Failed to get PR diff — PR #$pr_number left open" "$pr_url"
    return 1
  fi

  repo_root=$(git rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$DOTFILES_REPO_DIR")
  prompt_file="$repo_root/.github/review-prompt.md"
  if [[ ! -f "$prompt_file" ]]; then
    write_pr_body "$pr_number" "**Auto-review skipped**: review prompt file not found."
    notify_error "review-prompt.md missing — PR #$pr_number left open" "$pr_url"
    return 1
  fi

  prompt=$(cat "$prompt_file")

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
      echo "  ↳ reviewing with $reviewer_name (model: $model)..." >&2
      try_output="$(run_review_attempt "$reviewer" "$model" "$prompt" "$diff" "$repo_root" "$actual_model_file")"
      try_exit=$?

      if [[ $try_exit -eq 0 && -n "$try_output" ]]; then
        review="$try_output"
        verdict="$(printf '%s\n' "$review" | first_review_line)"
        reviewer_link="$(reviewer_url "$reviewer")"
        actual_model="$(cat "$actual_model_file" 2>/dev/null)"
        [[ -n "$actual_model" ]] || actual_model="$model"
        if [[ "$actual_model" != "$model" ]]; then
          footer="> Reviewed by **$reviewer_name** (model: \`$actual_model\`, configured: \`$model\`)"
        else
          footer="> Reviewed by **$reviewer_name** (model: \`$model\`)"
        fi
        [[ -n "$reviewer_link" ]] && footer="$footer via [$reviewer_name]($reviewer_link)"
        rm -f "$actual_model_file"

        write_pr_body "$pr_number" "$review

---
$footer"

        if [[ "$verdict" == APPROVED* ]]; then
          return 0
        fi

        notify_error "PR #$pr_number flagged by $reviewer_name review — needs manual check" "$pr_url"
        return 1
      fi

      if [[ $try_exit -eq 127 ]]; then
        attempts+=("$reviewer_name ($model): CLI not found")
      elif [[ -z "$try_output" ]]; then
        attempts+=("$reviewer_name ($model): empty response, exit=$try_exit")
      else
        attempts+=("$reviewer_name ($model): $(printf '%s\n' "$try_output" | first_review_line), exit=$try_exit")
      fi
      rm -f "$actual_model_file"
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
  notify_error "AI review failed — PR #$pr_number left open" "$pr_url"
  return 1
}

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

  # Stash any uncommitted work
  if ! git diff --quiet || ! git diff --cached --quiet; then
    git stash push -m "auto-backup-temp" > /dev/null 2>&1
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
echo "$CHANGED_FILES" | grep -q "^apps/ai-tools/gemini/" && SUMMARY="$SUMMARY, Gemini"
echo "$CHANGED_FILES" | grep -q "^apps/ai-tools/opencode/" && SUMMARY="$SUMMARY, OpenCode"
echo "$CHANGED_FILES" | grep -q "^cli/ssh/" && SUMMARY="$SUMMARY, SSH"
echo "$CHANGED_FILES" | grep -q "^cli/misc/" && SUMMARY="$SUMMARY, CLI misc"
echo "$CHANGED_FILES" | grep -q "^languages/node/" && SUMMARY="$SUMMARY, Node"
echo "$CHANGED_FILES" | grep -q "^languages/python/" && SUMMARY="$SUMMARY, Python"
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

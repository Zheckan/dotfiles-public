#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"

  [[ "$actual" == "$expected" ]] || fail "$label: expected [$expected], got [$actual]"
}

test_toml_config_loader_validates_and_flattens_settings() {
  local work_dir config output
  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-config-test.XXXXXX")"
  config="$work_dir/config.local.toml"

  cat > "$config" <<'TOML'
[backup]
mode = "pr-only"
rebase = false

[review]
enabled = true
reviewers = ["agy", "opencode"]

[review.models]
agy = ["gemini-3.7-flash-low", "claude-sonnet-4-6"]
opencode = ["opencode/muse-spark-1.2-contributor-free"]
opencode-go-api = ["opencode-go/deepseek-v4-flash"]

[review.reasoning.opencode]
"opencode/muse-spark-1.2-contributor-free" = "high"

[review.reasoning.opencode-go-api]
"opencode-go/deepseek-v4-flash" = "max"
TOML

  output="$(python3 "$SCRIPT_DIR/config.py" "$config")"
  [[ "$output" == *$'DOTFILES_AUTOBACKUP_MODE\tpr-only'* ]] ||
    fail "TOML mode was not flattened"
  [[ "$output" == *$'DOTFILES_AUTOBACKUP_REBASE\tfalse'* ]] ||
    fail "TOML boolean was not flattened"
  [[ "$output" == *$'DOTFILES_REVIEWERS\tagy,opencode'* ]] ||
    fail "TOML reviewer order was not flattened"
  [[ "$output" == *$'DOTFILES_REVIEW_AGY_MODELS\tgemini-3.7-flash-low,claude-sonnet-4-6'* ]] ||
    fail "TOML AGY models were not flattened"
  [[ "$output" == *$'DOTFILES_REVIEW_OPENCODE_REASONING\thigh'* ]] ||
    fail "TOML OpenCode reasoning was not flattened"
  [[ "$output" == *$'DOTFILES_REVIEW_OPENCODE_GO_API_REASONING\tmax'* ]] ||
    fail "TOML OpenCode Go reasoning was not flattened"
  [[ "$output" == *$'DOTFILES_REVIEW_CLAUDE_REASONING\t'* ]] ||
    fail "TOML Claude reasoning key was not emitted"

  cat > "$config" <<'TOML'
[backup]
mode = "pr-only"
rebase = true

[review]
enabled = true
reviewers = ["claude"]

[review.models]
claude = ["haiku"]

[review.reasoning.claude]
haiku = "high"
TOML
  output="$(python3 "$SCRIPT_DIR/config.py" "$config")"
  [[ "$output" == *$'DOTFILES_REVIEW_CLAUDE_REASONING\tdefault'* ]] ||
    fail "legacy incompatible Haiku effort did not fall back to default"

  cat > "$config" <<'TOML'
[backup]
mode = "main-pc"
rebase = true
unexpected = "unsafe"

[review]
enabled = false
reviewers = []

[review.models]
TOML
  if python3 "$SCRIPT_DIR/config.py" "$config" >"$work_dir/output" 2>"$work_dir/error"; then
    fail "unknown TOML keys should be rejected"
  fi
  [[ "$(<"$work_dir/error")" == *"unsupported key"* ]] ||
    fail "invalid TOML did not explain the unsupported key"

  rm -rf "$work_dir"
}

write_test_config() {
  local path="$1"

  cat > "$path" <<'TOML'
[backup]
mode = "test"
rebase = true

[review]
enabled = true
reviewers = ["claude"]

[review.models]
claude = ["default"]

[review.reasoning.claude]
default = "default"
TOML
}

source_helpers() {
  local stub_dir config_file
  stub_dir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-review-test-stubs.XXXXXX")"
  config_file="$stub_dir/config.local.toml"
  printf '#!/usr/bin/env bash\n[[ "$1" == push ]] && exit 1\n/usr/bin/git "$@"\n' > "$stub_dir/git"
  chmod +x "$stub_dir/git"
  write_test_config "$config_file"

  PATH="$stub_dir:$PATH"
  DOTFILES_AUTOBACKUP_SOURCE_ONLY=true
  DOTFILES_AUTOBACKUP_CONFIG_FILE="$config_file"
  DOTFILES_REPO_DIR="$REPO_DIR"
  export PATH DOTFILES_AUTOBACKUP_SOURCE_ONLY DOTFILES_AUTOBACKUP_CONFIG_FILE DOTFILES_REPO_DIR
  source "$SCRIPT_DIR/auto-commit.sh" --test
}

test_missing_local_config_stops_before_backup() {
  local output exit_code

  set +e
  output="$(
    env -i \
      HOME="$HOME" \
      PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
      DOTFILES_AUTOBACKUP_SOURCE_ONLY=true \
      DOTFILES_AUTOBACKUP_CONFIG_FILE="/tmp/does-not-exist-dotfiles-config.toml" \
      DOTFILES_REPO_DIR="$REPO_DIR" \
      /bin/bash -c 'source "$1/auto-commit.sh"' _ "$SCRIPT_DIR" 2>&1
  )"
  exit_code=$?
  set -e

  assert_eq "2" "$exit_code" "missing local config exit"
  [[ "$output" == *"auto-backup/configure.sh"* ]] ||
    fail "missing config error does not provide setup command"
}

test_notification_self_test_runs_without_backup_config() {
  local work_dir output exit_code
  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-notification-cli-test.XXXXXX")"

  set +e
  output="$(
    env -i \
      HOME="$HOME" \
      PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
      DOTFILES_AUTOBACKUP_CONFIG_FILE="$work_dir/does-not-exist.toml" \
      /bin/bash -c \
        'terminal-notifier() { printf "%s\n" "didGrant:1 hasError:0"; }; source "$1" --test-notification' \
        _ "$SCRIPT_DIR/auto-commit.sh" 2>&1
  )"
  exit_code=$?
  set -e

  assert_eq "0" "$exit_code" "notification self-test exit"
  [[ "$output" == *"Test notification sent"* ]] ||
    fail "notification self-test did not confirm the send attempt"

  rm -rf "$work_dir"
}

test_setup_notification_click_copies_command() {
  local work_dir args
  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-notification-test.XXXXXX")"

  terminal-notifier() {
    printf '%s\n' "$@" > "$work_dir/args"
  }
  DOTFILES_AUTOBACKUP_SOURCE_ONLY=false
  notify_setup_required 2>/dev/null
  DOTFILES_AUTOBACKUP_SOURCE_ONLY=true
  unset -f terminal-notifier

  args="$(<"$work_dir/args")"
  [[ "$args" == *"-execute"* && "$args" == *"/usr/bin/pbcopy"* ]] ||
    fail "setup notification does not copy its command when clicked"
  [[ "$args" == *"$SCRIPT_DIR/configure.sh"* ]] ||
    fail "setup notification click action omitted the configure command"
  rm -rf "$work_dir"
}

test_notification_denial_falls_back_to_osascript() {
  local work_dir fallback_file delivery_exit
  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-notification-fallback-test.XXXXXX")"
  fallback_file="$work_dir/osascript-called"

  terminal-notifier() {
    printf '%s\n' 'didGrant:0 hasError:1'
    return 0
  }

  osascript() {
    cat > /dev/null
    printf '%s\n' called > "$fallback_file"
  }

  set +e
  deliver_notification "Backup finished" "" "" 2> "$work_dir/error"
  delivery_exit=$?
  set -e
  unset -f terminal-notifier osascript

  assert_eq "0" "$delivery_exit" "notification fallback exit"
  assert_eq "called" "$(<"$fallback_file")" "notification fallback invocation"
  grep -Fq 'terminal-notifier denied notification access' "$work_dir/error" ||
    fail "notification denial was not reported"

  rm -rf "$work_dir"
}

test_notification_failure_is_written_to_stderr() {
  local work_dir delivery_exit
  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-notification-error-test.XXXXXX")"

  terminal-notifier() {
    printf '%s\n' 'notification service unavailable'
    return 1
  }

  osascript() {
    cat > /dev/null
    printf '%s\n' 'notifications are disabled'
    return 1
  }

  set +e
  deliver_notification "Backup finished" "" "" 2> "$work_dir/error"
  delivery_exit=$?
  set -e
  unset -f terminal-notifier osascript

  assert_eq "1" "$delivery_exit" "notification delivery failure exit"
  grep -Fq 'macOS notification delivery failed' "$work_dir/error" ||
    fail "notification failure was not written to stderr"
  grep -Fq -- '--test-notification' "$work_dir/error" ||
    fail "notification failure did not provide the self-test command"

  rm -rf "$work_dir"
}

test_deprecated_reviewer_flag_notifies_and_copies_migration_command() {
  local work_dir args
  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-flag-notification-test.XXXXXX")"

  terminal-notifier() {
    printf '%s\n' "$@" > "$work_dir/args"
  }
  DOTFILES_AUTOBACKUP_SOURCE_ONLY=false
  notify_deprecated_reviewer_flag "--agy" 2>/dev/null
  DOTFILES_AUTOBACKUP_SOURCE_ONLY=true
  unset -f terminal-notifier

  args="$(<"$work_dir/args")"
  [[ "$args" == *"Deprecated reviewer flag: --agy"* ]] ||
    fail "deprecated reviewer notification omitted the flag"
  [[ "$args" == *"-execute"* && "$args" == *"/usr/bin/pbcopy"* ]] ||
    fail "deprecated reviewer notification does not copy migration command"
  [[ "$args" == *"$SCRIPT_DIR/configure.sh"* ]] ||
    fail "deprecated reviewer notification omitted configure command"
  rm -rf "$work_dir"
}

test_reviewer_flags_are_rejected_with_migration_guidance() {
  local work_dir config output exit_code
  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-flag-test.XXXXXX")"
  config="$work_dir/config.local.toml"
  write_test_config "$config"

  set +e
  output="$(
    env -i \
      HOME="$HOME" \
      PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
      DOTFILES_AUTOBACKUP_SOURCE_ONLY=true \
      DOTFILES_AUTOBACKUP_CONFIG_FILE="$config" \
      DOTFILES_REPO_DIR="$REPO_DIR" \
      /bin/bash -c 'source "$1/auto-commit.sh" --agy' _ "$SCRIPT_DIR" 2>&1
  )"
  exit_code=$?
  set -e

  assert_eq "2" "$exit_code" "retired reviewer flag exit"
  [[ "$output" == *"reviewer flags were removed"* && "$output" == *"auto-backup/configure.sh"* ]] ||
    fail "retired reviewer flag does not provide migration guidance"
  rm -rf "$work_dir"
}

test_install_requires_valid_local_config_before_side_effects() {
  local work_dir output exit_code
  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-install-config-test.XXXXXX")"

  set +e
  output="$(
    env -i \
      HOME="$work_dir/home" \
      PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
      DOTFILES_AUTOBACKUP_CONFIG_FILE="$work_dir/missing.toml" \
      /bin/bash "$SCRIPT_DIR/install.sh" 2>&1
  )"
  exit_code=$?
  set -e

  assert_eq "1" "$exit_code" "install missing config exit"
  [[ "$output" == *"configure.sh"* ]] ||
    fail "install missing config error does not provide setup command"
  [[ ! -e "$work_dir/home/Library" ]] ||
    fail "install changed LaunchAgent state before validating config"

  rm -rf "$work_dir"
}

test_install_validates_inherited_opencode_go_key() {
  local work_dir config validation_file
  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-install-key-test.XXXXXX")"
  config="$work_dir/config.local.toml"
  validation_file="$work_dir/validation"

  cat > "$config" <<'TOML'
[backup]
mode = "device-only"
rebase = true

[review]
enabled = true
reviewers = ["opencode-go-api"]

[review.models]
opencode-go-api = ["opencode-go/deepseek-v4-flash"]
TOML

  (
    DOTFILES_AUTOBACKUP_INSTALL_SOURCE_ONLY=true
    DOTFILES_AUTOBACKUP_CONFIG_FILE="$config"
    DOTFILES_OPENCODE_GO_ENV_FILE="$work_dir/missing.env"
    OPENCODE_GO_API_KEY="inherited-test-key"
    export DOTFILES_AUTOBACKUP_INSTALL_SOURCE_ONLY DOTFILES_AUTOBACKUP_CONFIG_FILE
    export DOTFILES_OPENCODE_GO_ENV_FILE OPENCODE_GO_API_KEY
    source "$SCRIPT_DIR/install.sh" > /dev/null

    python3() {
      if [[ "$1" == "$SCRIPT_DIR/config.py" ]]; then
        command python3 "$@"
      elif [[ "$2" == "validate" ]]; then
        [[ "${OPENCODE_GO_API_KEY:-}" == "inherited-test-key" ]] || return 9
        [[ "$3" == "opencode-go/deepseek-v4-flash" ]] || return 10
        printf 'validated\n' > "$validation_file"
      else
        return 11
      fi
    }
    validate_machine_config > /dev/null
  )

  assert_eq "validated" "$(<"$validation_file")" \
    "install validates inherited OpenCode Go key"
  rm -rf "$work_dir"
}

test_preface_approved_is_normalized() {
  local input output meta
  input="$(mktemp)"
  output="$(mktemp)"
  meta="$(mktemp)"

  cat > "$input" <<'FIXTURE'
I will apply the repository review rules.
APPROVED

### Summary
Clean backup.
FIXTURE

  normalize_review_output "$input" "$output" "$meta"
  assert_eq "APPROVED" "$(sed -n '1p' "$output")" "approved verdict first line"
  assert_eq "removed 1 preface line before APPROVED" "$(cat "$meta")" "approved normalization metadata"
}

test_preface_changes_requested_is_normalized() {
  local input output meta
  input="$(mktemp)"
  output="$(mktemp)"
  meta="$(mktemp)"

  cat > "$input" <<'FIXTURE'
Reviewing with the requested policy.
CHANGES_REQUESTED

### Issues
Secret detected.
FIXTURE

  normalize_review_output "$input" "$output" "$meta"
  assert_eq "CHANGES_REQUESTED" "$(sed -n '1p' "$output")" "changes requested verdict first line"
  assert_eq "removed 1 preface line before CHANGES_REQUESTED" "$(cat "$meta")" "changes requested normalization metadata"
}

test_no_verdict_is_invalid() {
  local input output meta
  input="$(mktemp)"
  output="$(mktemp)"
  meta="$(mktemp)"

  printf '%s\n' 'Looks safe to me.' > "$input"

  if normalize_review_output "$input" "$output" "$meta"; then
    fail "missing verdict should be invalid"
  fi
}

test_multiple_verdicts_are_invalid() {
  local input output meta
  input="$(mktemp)"
  output="$(mktemp)"
  meta="$(mktemp)"

  printf '%s\n' 'APPROVED' 'CHANGES_REQUESTED' > "$input"

  if normalize_review_output "$input" "$output" "$meta"; then
    fail "multiple verdicts should be invalid"
  fi
}

test_correct_output_is_unchanged() {
  local input output meta
  input="$(mktemp)"
  output="$(mktemp)"
  meta="$(mktemp)"

  printf '%s\n\n%s\n' 'APPROVED' '### Summary' > "$input"

  normalize_review_output "$input" "$output" "$meta"
  assert_eq "$(cat "$input")" "$(cat "$output")" "already correct output"
  assert_eq "" "$(cat "$meta")" "no normalization metadata"
}

test_claude_stream_reports_response_and_auxiliary_models() {
  local stream review model auxiliary
  stream="$(mktemp)"
  review="$(mktemp)"
  model="$(mktemp)"
  auxiliary="$(mktemp)"

  cat > "$stream" <<'JSONL'
{"type":"system","subtype":"init","model":"claude-opus-5"}
{"type":"assistant","message":{"model":"claude-opus-5","role":"assistant","content":[{"type":"text","text":"APPROVED\n\n### Summary\nClean backup."}]},"parent_tool_use_id":null}
{"type":"result","subtype":"success","is_error":false,"result":"APPROVED\n\n### Summary\nClean backup.","modelUsage":{"claude-haiku-4-5-20251001":{},"claude-opus-5":{}}}
JSONL

  parse_claude_stream_review "$stream" "$review" "$model" "$auxiliary"

  assert_eq "APPROVED

### Summary
Clean backup." "$(<"$review")" "Claude stream review"
  assert_eq "claude-opus-5" "$(<"$model")" "Claude response model"
  assert_eq "claude-haiku-4-5-20251001" "$(<"$auxiliary")" \
    "Claude auxiliary models"

  rm -f "$stream" "$review" "$model" "$auxiliary"
}

test_claude_stream_empty_result_uses_final_assistant_message() {
  local stream review model auxiliary
  stream="$(mktemp)"
  review="$(mktemp)"
  model="$(mktemp)"
  auxiliary="$(mktemp)"

  cat > "$stream" <<'JSONL'
{"type":"assistant","message":{"model":"claude-opus-5","content":[{"type":"text","text":"I am checking the repository."}]},"parent_tool_use_id":null}
{"type":"assistant","message":{"model":"claude-opus-5","content":[{"type":"text","text":"APPROVED\n\n### Summary\nClean backup."}]},"parent_tool_use_id":null}
{"type":"result","subtype":"success","is_error":false,"result":"","modelUsage":{"claude-opus-5":{}}}
JSONL

  parse_claude_stream_review "$stream" "$review" "$model" "$auxiliary"

  assert_eq "APPROVED

### Summary
Clean backup." "$(<"$review")" "Claude empty-result fallback"

  rm -f "$stream" "$review" "$model" "$auxiliary"
}

test_claude_review_uses_stream_response_model() {
  local work_dir args_file actual_model_file detail_file auxiliary_file output review_exit
  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-claude-stream-test.XXXXXX")"
  args_file="$work_dir/args"
  actual_model_file="$work_dir/model"
  detail_file="$work_dir/detail"
  auxiliary_file="$work_dir/auxiliary"

  claude() {
    printf '%s\n' "$@" > "$args_file"
    cat > /dev/null
    cat <<'JSONL'
{"type":"assistant","message":{"model":"claude-opus-5","content":[{"type":"text","text":"APPROVED\n\n### Summary\nClean backup."}]},"parent_tool_use_id":null}
{"type":"result","subtype":"success","is_error":false,"result":"APPROVED\n\n### Summary\nClean backup.","modelUsage":{"claude-haiku-4-5-20251001":{},"claude-opus-5":{}}}
JSONL
  }

  set +e
  output="$(run_claude_review \
    "opus" \
    "Apply the review policy." \
    "diff --git a/file b/file" \
    "$actual_model_file" \
    "$detail_file" \
    "$auxiliary_file" \
    "high")"
  review_exit=$?
  set -e
  unset -f claude

  assert_eq "0" "$review_exit" "Claude stream adapter exit"
  assert_eq "APPROVED

### Summary
Clean backup." "$output" "Claude stream adapter output"
  assert_eq "claude-opus-5" "$(<"$actual_model_file")" "Claude stream actual model"
  assert_eq "claude-haiku-4-5-20251001" "$(<"$auxiliary_file")" \
    "Claude stream auxiliary model"
  grep -Fxq -- "stream-json" "$args_file" || fail "Claude stream output format missing"
  grep -Fxq -- "--verbose" "$args_file" || fail "Claude verbose stream flag missing"
  grep -Fxq -- "--effort" "$args_file" || fail "Claude effort flag missing"
  grep -Fxq -- "high" "$args_file" || fail "Claude effort value missing"

  rm -rf "$work_dir"
}

test_claude_haiku_uses_thinking_toggle_instead_of_effort() {
  local work_dir args_file env_file actual_model_file detail_file output
  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-claude-thinking-test.XXXXXX")"
  args_file="$work_dir/args"
  env_file="$work_dir/env"
  actual_model_file="$work_dir/model"
  detail_file="$work_dir/detail"

  claude() {
    printf '%s\n' "$@" > "$args_file"
    printf '%s\n%s' \
      "${CLAUDE_CODE_DISABLE_THINKING:-}" \
      "${MAX_THINKING_TOKENS:-}" > "$env_file"
    cat > /dev/null
    cat <<'JSONL'
{"type":"assistant","message":{"model":"claude-haiku-4-5","content":[{"type":"text","text":"APPROVED"}]},"parent_tool_use_id":null}
{"type":"result","subtype":"success","is_error":false,"result":"APPROVED","modelUsage":{"claude-haiku-4-5":{}}}
JSONL
  }

  output="$(run_claude_review \
    "haiku" \
    "Apply the review policy." \
    "diff --git a/file b/file" \
    "$actual_model_file" \
    "$detail_file" \
    "" \
    "off")"
  assert_eq "APPROVED" "$output" "Claude Haiku thinking-off output"
  assert_eq "1" "$(sed -n '1p' "$env_file")" "Claude Haiku thinking-off environment"
  if grep -Fxq -- "--effort" "$args_file"; then
    fail "Claude Haiku thinking toggle was sent as an effort level"
  fi

  export CLAUDE_CODE_DISABLE_THINKING=1 MAX_THINKING_TOKENS=0
  output="$(run_claude_review \
    "haiku" \
    "Apply the review policy." \
    "diff --git a/file b/file" \
    "$actual_model_file" \
    "$detail_file" \
    "" \
    "on")"
  unset CLAUDE_CODE_DISABLE_THINKING MAX_THINKING_TOKENS
  assert_eq "APPROVED" "$output" "Claude Haiku thinking-on output"
  assert_eq "" "$(sed -n '1p' "$env_file")" \
    "Claude Haiku thinking-on clears inherited disable flag"
  assert_eq "" "$(sed -n '2p' "$env_file")" \
    "Claude Haiku thinking-on clears inherited zero-token budget"
  grep -Fxq -- "--settings" "$args_file" ||
    fail "Claude Haiku thinking-on setting missing"
  grep -Fxq -- '{"alwaysThinkingEnabled":true}' "$args_file" ||
    fail "Claude Haiku thinking-on value missing"

  unset -f claude
  rm -rf "$work_dir"
}

test_codex_and_opencode_reviews_apply_configured_reasoning() {
  local work_dir codex_args opencode_args actual_model_file detail_file output
  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-reasoning-adapters-test.XXXXXX")"
  codex_args="$work_dir/codex-args"
  opencode_args="$work_dir/opencode-args"
  actual_model_file="$work_dir/model"
  detail_file="$work_dir/detail"

  codex() {
    printf '%s\n' "$@" > "$codex_args"
    cat > /dev/null
    printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"APPROVED"}}'
  }
  output="$(run_codex_review \
    "gpt-5.6-sol" \
    "Apply the review policy." \
    "diff --git a/file b/file" \
    "$REPO_DIR" \
    "$actual_model_file" \
    "$detail_file" \
    "xhigh")"
  unset -f codex

  assert_eq "APPROVED" "$output" "Codex reasoning adapter output"
  grep -Fxq -- "model_reasoning_effort=\"xhigh\"" "$codex_args" ||
    fail "Codex reasoning override missing"

  opencode() {
    printf '%s\n' "$@" > "$opencode_args"
    cat > /dev/null
    printf '%s\n' '{"type":"text","part":{"id":"review","text":"APPROVED"}}'
  }
  output="$(run_opencode_review \
    "opencode-go/grok-4.6" \
    "Apply the review policy." \
    "diff --git a/file b/file" \
    "$REPO_DIR" \
    "$actual_model_file" \
    "$detail_file" \
    "high")"
  unset -f opencode

  assert_eq "APPROVED" "$output" "OpenCode reasoning adapter output"
  grep -Fxq -- "--variant" "$opencode_args" || fail "OpenCode variant flag missing"
  grep -Fxq -- "high" "$opencode_args" || fail "OpenCode variant value missing"

  rm -rf "$work_dir"
}

test_sanitize_attempt_reason() {
  local raw sanitized
  raw='API_TOKEN=abcdef123456 password: hunter2 Failed to authenticate. API Error: 401 Invalid authentication credentials'
  sanitized="$(sanitize_review_detail "$raw")"

  [[ "$sanitized" != *hunter2* ]] || fail "password was not redacted"
  [[ "$sanitized" != *abcdef123456* ]] || fail "token was not redacted"
  [[ "$sanitized" == *"401 Invalid authentication credentials"* ]] || fail "auth error detail was lost"
}

test_sanitize_authorization_bearer() {
  local raw sanitized
  raw='Authorization: Bearer sample-bearer-token-value failed with 401'
  sanitized="$(sanitize_review_detail "$raw")"

  [[ "$sanitized" != *sample-bearer-token-value* ]] || fail "authorization bearer token was not redacted"
  [[ "$sanitized" == *"Authorization=<redacted>"* ]] || fail "authorization header was not redacted"
  [[ "$sanitized" == *"failed with 401"* ]] || fail "non-secret diagnostic detail was lost"
}

test_sanitize_claude_json_auth_error() {
  local raw sanitized
  raw='{"type":"result","subtype":"success","is_error":true,"api_error_status":401,"duration_ms":2518,"result":"Failed to authenticate. API Error: 401 Invalid authentication credentials","stop_reason":"stop_sequence"}'
  sanitized="$(sanitize_review_detail "$raw")"

  assert_eq "API 401: Failed to authenticate. Invalid authentication credentials." "$sanitized" "claude json auth detail"
}

test_auto_commit_stashes_untracked_work() {
  if ! grep -q 'git stash push --include-untracked -m "auto-backup-temp"' "$SCRIPT_DIR/auto-commit.sh"; then
    fail "auto-commit does not include untracked files in its temporary stash"
  fi
}

test_run_backup_skips_refresh_when_dirty() {
  grep -q 'worktree_has_local_changes' "$SCRIPT_DIR/run-backup.sh" ||
    fail "run-backup does not check local worktree state"
  grep -q 'skipping script refresh before auto-commit can stash them' "$SCRIPT_DIR/run-backup.sh" ||
    fail "run-backup does not skip pre-run script refresh when dirty"
}

test_noninteractive_runtime_finds_opencode_installer_binary() {
  local fake_home resolved
  fake_home="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-opencode-home.XXXXXX")"
  mkdir -p "$fake_home/.opencode/bin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$fake_home/.opencode/bin/opencode"
  chmod +x "$fake_home/.opencode/bin/opencode"
  write_test_config "$fake_home/config.local.toml"

  resolved="$(
    env -i \
      HOME="$fake_home" \
      PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
      DOTFILES_AUTOBACKUP_SOURCE_ONLY=true \
      DOTFILES_AUTOBACKUP_CONFIG_FILE="$fake_home/config.local.toml" \
      DOTFILES_REPO_DIR="$REPO_DIR" \
      /bin/bash -c 'source "$1/auto-commit.sh" --test; command -v opencode' _ "$SCRIPT_DIR"
  )"

  assert_eq "$fake_home/.opencode/bin/opencode" "$resolved" "noninteractive OpenCode path"
  grep -Fq '$HOME/.opencode/bin' "$SCRIPT_DIR/run-backup.sh" ||
    fail "run-backup does not expose the OpenCode installer directory"
  rm -rf "$fake_home"
}

test_agy_review_uses_read_only_streaming_interface() {
  local stub_dir args_file input_file actual_model_file detail_file output old_path
  stub_dir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-agy-stub.XXXXXX")"
  args_file="$stub_dir/args"
  input_file="$stub_dir/input"
  actual_model_file="$stub_dir/model"
  detail_file="$stub_dir/detail"

  cat > "$stub_dir/agy" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$AGY_ARGS_FILE"
cat > "$AGY_INPUT_FILE"
printf '%s\n' '{"event":"result","result":{"status":"SUCCESS","response":"APPROVED\n\n### Summary\nClean backup."}}'
STUB
  chmod +x "$stub_dir/agy"

  old_path="$PATH"
  PATH="$stub_dir:$PATH"
  export AGY_ARGS_FILE="$args_file" AGY_INPUT_FILE="$input_file"
  output="$(run_agy_review \
    "gemini-3.7-flash-low" \
    "Apply the review policy." \
    "diff --git a/file b/file" \
    "$REPO_DIR" \
    "$actual_model_file" \
    "$detail_file")"
  PATH="$old_path"
  unset AGY_ARGS_FILE AGY_INPUT_FILE

  assert_eq "APPROVED

### Summary
Clean backup." "$output" "AGY review output"
  assert_eq "gemini-3.7-flash-low" "$(cat "$actual_model_file")" "AGY actual model"
  grep -Fxq -- "--input-format" "$args_file" || fail "AGY input format flag missing"
  grep -Fxq -- "stream-json" "$args_file" || fail "AGY stream-json argument missing"
  grep -Fxq -- "--output-format" "$args_file" || fail "AGY output format flag missing"
  grep -Fxq -- "--mode" "$args_file" || fail "AGY plan mode flag missing"
  grep -Fxq -- "plan" "$args_file" || fail "AGY plan mode argument missing"
  grep -Fxq -- "--sandbox" "$args_file" || fail "AGY sandbox flag missing"
  grep -Fq "Apply the review policy." "$input_file" || fail "AGY prompt missing from stream input"
  grep -Fq "diff --git a/file b/file" "$input_file" || fail "AGY diff missing from stream input"

  rm -rf "$stub_dir"
}

test_agy_review_preserves_local_input_diagnostic() {
  local work_dir actual_model_file detail_file review_exit
  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-agy-input-test.XXXXXX")"
  actual_model_file="$work_dir/model"
  detail_file="$work_dir/detail"

  agy() {
    fail "AGY should not run after local input preparation fails"
  }

  set +e
  run_agy_review \
    "gemini-3.7-flash-low" \
    "Apply the review policy." \
    $'diff with invalid byte \xAD' \
    "$REPO_DIR" \
    "$actual_model_file" \
    "$detail_file" > /dev/null
  review_exit=$?
  set -e
  unset -f agy

  assert_eq "78" "$review_exit" "AGY local input failure exit"
  grep -Fq "can't decode byte 0xad" "$detail_file" ||
    fail "AGY discarded the local input diagnostic"

  rm -rf "$work_dir"
}

test_opencode_go_api_review_uses_separate_key_and_helper() {
  local work_dir actual_model_file detail_file output
  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-opencode-go-test.XXXXXX")"
  actual_model_file="$work_dir/model"
  detail_file="$work_dir/detail"
  OPENCODE_GO_ENV_FILE="$work_dir/.env"
  unset OPENCODE_GO_API_KEY

  python3() {
    case "$2" in
      read-key)
        printf 'test-api-key\n'
        ;;
      review)
        [[ "${OPENCODE_GO_API_KEY:-}" == "test-api-key" ]] || return 9
        [[ "$3" == "opencode-go/deepseek-v4-flash" ]] || return 10
        grep -Fq "Apply the review policy." "$4" || return 11
        grep -Fq "diff --git a/file b/file" "$4" || return 12
        [[ "$5" == "max" ]] || return 14
        printf 'APPROVED\n\n### Summary\nClean backup.\n'
        ;;
      *)
        return 13
        ;;
    esac
  }

  output="$(run_opencode_go_api_review \
    "opencode-go/deepseek-v4-flash" \
    "Apply the review policy." \
    "diff --git a/file b/file" \
    "$REPO_DIR" \
    "$actual_model_file" \
    "$detail_file" \
    "max")"
  unset -f python3

  assert_eq "APPROVED

### Summary
Clean backup." "$output" "OpenCode Go API review output"
  assert_eq "opencode-go/deepseek-v4-flash" "$(<"$actual_model_file")" \
    "OpenCode Go actual model"
  [[ ! -s "$detail_file" ]] || fail "OpenCode Go API review leaked diagnostics"

  rm -rf "$work_dir"
}

test_autobackup_uses_nvm_default_for_npm_backup() {
  local script

  for script in "$SCRIPT_DIR/run-backup.sh" "$SCRIPT_DIR/auto-commit.sh"; do
    grep -Fq 'source "$NVM_DIR/nvm.sh" --no-use' "$script" ||
      fail "$script does not load nvm for non-interactive use"
    grep -Fq 'nvm use --silent default' "$script" ||
      fail "$script does not activate nvm's configured default version"
    if grep -Fq 'ls "$HOME/.nvm/versions/node/"' "$script"; then
      fail "$script still chooses Node by lexicographic directory order"
    fi
  done

  if [[ -f "$REPO_DIR/apps/Brewfile" ]]; then
    grep -q '^npm ' "$REPO_DIR/apps/Brewfile" ||
      fail "Brewfile does not contain the npm globals returned by the default Node dump"
  fi
}

test_review_prompt_blocks_wholesale_package_backup_deletions() {
  local prompt="$REPO_DIR/.github/review-prompt.md"
  local cli_prompt

  grep -Fq 'all `npm` entries' "$prompt" ||
    fail "review prompt does not name wholesale npm entry removal as an example"
  grep -Fq 'must return `CHANGES_REQUESTED`' "$prompt" ||
    fail "review prompt does not require a blocking verdict for package backup loss"
  grep -Fq 'section is critical, not a warning' "$prompt" ||
    fail "package-change warning does not defer wholesale section removal to critical handling"
  grep -Fq 'Any critical finding requires `CHANGES_REQUESTED`' "$prompt" ||
    fail "review prompt does not map critical findings to the blocking verdict"

  for cli_prompt in \
    "$REPO_DIR/AGENTS.md" \
    "$REPO_DIR/.github/instructions/backup-review.instructions.md"; do
    grep -Fq 'all `npm` entries' "$cli_prompt" ||
      fail "$cli_prompt does not name wholesale npm entry removal as an example"
    grep -Fq '`CHANGES_REQUESTED`' "$cli_prompt" ||
      fail "$cli_prompt does not require a blocking verdict for package backup loss"
  done
}

test_review_pr_escapes_invalid_utf8_before_review() {
  local captured_diff review_exit
  captured_diff="$(mktemp)"

  gh() {
    if [[ "$1" == "pr" && "$2" == "diff" ]]; then
      printf 'diff --git a/history/.zsh_history b/history/.zsh_history\n+bad-byte-\255\n'
      return 0
    fi
    return 1
  }

  configured_reviewers() {
    printf '%s\n' claude
  }

  models_for_reviewer() {
    printf '%s\n' opus
  }

  run_review_attempt() {
    local diff="$4"
    local actual_model_file="$6"
    printf '%s' "$diff" > "$captured_diff"
    printf '%s' 'claude-opus-5' > "$actual_model_file"
    printf '%s\n' 'APPROVED' '' '### Summary' 'Clean backup.'
  }

  write_pr_body() { :; }
  upsert_review_diagnostics_comment() { :; }
  delete_review_diagnostics_comment() { :; }

  set +e
  review_pr "267" "https://github.com/example/repo/pull/267"
  review_exit=$?
  set -e

  assert_eq "0" "$review_exit" "invalid UTF-8 review exit"
  iconv -f UTF-8 -t UTF-8 "$captured_diff" > /dev/null 2>&1 ||
    fail "review adapter received invalid UTF-8"
  grep -Fq '\xad' "$captured_diff" ||
    fail "invalid review byte was not preserved as a visible escape"

  rm -f "$captured_diff"
}

test_review_pr_skips_remaining_models_after_adapter_failure() {
  local attempts_file review_exit
  attempts_file="$(mktemp)"

  gh() {
    if [[ "$1" == "pr" && "$2" == "diff" ]]; then
      printf '%s\n' 'diff --git a/file b/file'
      return 0
    fi
    return 1
  }

  configured_reviewers() {
    printf '%s\n' opencode-go-api claude
  }

  models_for_reviewer() {
    case "$1" in
      opencode-go-api) printf '%s\n' opencode-go/grok-4.6 opencode-go/kimi-k3 ;;
      claude) printf '%s\n' opus ;;
    esac
  }

  run_review_attempt() {
    local reviewer="$1"
    local model="$2"
    local actual_model_file="$6"
    local detail_file="$7"
    printf '%s:%s\n' "$reviewer" "$model" >> "$attempts_file"

    if [[ "$reviewer" == "opencode-go-api" ]]; then
      printf '%s' 'local adapter configuration failed' > "$detail_file"
      return 78
    fi

    printf '%s' 'claude-opus-5' > "$actual_model_file"
    printf '%s\n' 'APPROVED' '' '### Summary' 'Clean backup.'
  }

  write_pr_body() { :; }
  upsert_review_diagnostics_comment() { :; }
  delete_review_diagnostics_comment() { :; }

  set +e
  review_pr "267" "https://github.com/example/repo/pull/267"
  review_exit=$?
  set -e

  assert_eq "0" "$review_exit" "adapter failure fallback exit"
  assert_eq "opencode-go-api:opencode-go/grok-4.6
claude:opus" "$(<"$attempts_file")" \
    "adapter failure should skip remaining models"

  rm -f "$attempts_file"
}

test_review_pr_falls_back_and_writes_diagnostics() {
  local body comment
  LAST_PR_BODY=""
  LAST_DIAGNOSTICS_COMMENT=""
  DELETE_DIAGNOSTICS_CALLED=false

  gh() {
    if [[ "$1" == "pr" && "$2" == "diff" ]]; then
      printf '%s\n' 'diff --git a/file b/file'
      return 0
    fi
    return 1
  }

  configured_reviewers() {
    printf '%s\n' claude codex
  }

  models_for_reviewer() {
    case "$1" in
      claude) printf '%s\n' default sonnet haiku ;;
      codex) printf '%s\n' default ;;
    esac
  }

  run_review_attempt() {
    local reviewer="$1"
    local model="$2"
    local actual_model_file="$6"
    local detail_file="$7"

    if [[ "$reviewer" == "claude" ]]; then
      printf '%s\n' '{"type":"result","subtype":"success","is_error":true,"api_error_status":401,"duration_ms":2518,"result":"Failed to authenticate. API Error: 401 Invalid authentication credentials","stop_reason":"stop_sequence"}' > "$detail_file"
      return 1
    fi

    if [[ "$reviewer" == "codex" && "$model" == "default" ]]; then
      printf '%s' 'gpt-5.5' > "$actual_model_file"
      cat <<'FIXTURE'
I will apply the repository review rules.
APPROVED

### Summary
Clean backup.
FIXTURE
      return 0
    fi

    return 64
  }

  write_pr_body() {
    LAST_PR_BODY="$2"
  }

  upsert_review_diagnostics_comment() {
    LAST_DIAGNOSTICS_COMMENT="$2"
  }

  delete_review_diagnostics_comment() {
    DELETE_DIAGNOSTICS_CALLED=true
  }

  set +e
  review_pr "146" "https://github.com/example/repo/pull/146"
  local review_exit=$?
  set -e
  assert_eq "0" "$review_exit" "review_pr exit"

  body="$LAST_PR_BODY"
  comment="$LAST_DIAGNOSTICS_COMMENT"

  assert_eq "APPROVED" "$(printf '%s\n' "$body" | sed -n '1p')" "review body starts with approved"
  [[ "$body" == *'Reviewed by **Codex** (model: `gpt-5.5`, configured: `default`)'* ]] || fail "codex footer missing"
  [[ "$comment" == *'<!-- dotfiles-auto-review-diagnostics -->'* ]] || fail "diagnostics marker missing"
  [[ "$comment" == *'Final reviewer: Codex (model: `gpt-5.5`, configured: `default`)'* ]] || fail "final reviewer diagnostic missing"
  [[ "$comment" == *'Fallback reason:'* ]] || fail "fallback reason heading missing"
  [[ "$comment" == *'Claude authentication failed for all configured models:'* ]] || fail "compact claude auth diagnostic missing"
  [[ "$comment" == *'- `default`: API 401, invalid authentication credentials'* ]] || fail "default claude failure diagnostic missing"
  [[ "$comment" == *'- `sonnet`: API 401, invalid authentication credentials'* ]] || fail "sonnet claude failure diagnostic missing"
  [[ "$comment" == *'- `haiku`: API 401, invalid authentication credentials'* ]] || fail "haiku claude failure diagnostic missing"
  [[ "$comment" != *'{"type":"result"'* ]] || fail "raw claude json leaked into diagnostics"
  [[ "$comment" == *'Codex (`default`): removed 1 preface line before APPROVED'* ]] || fail "normalization diagnostic missing"
  assert_eq "false" "$DELETE_DIAGNOSTICS_CALLED" "delete diagnostics should not run when diagnostics exist"
}

test_review_pr_deletes_stale_diagnostics_on_clean_success() {
  LAST_PR_BODY=""
  LAST_DIAGNOSTICS_COMMENT=""
  DELETE_DIAGNOSTICS_CALLED=false

  gh() {
    if [[ "$1" == "pr" && "$2" == "diff" ]]; then
      printf '%s\n' 'diff --git a/file b/file'
      return 0
    fi
    return 1
  }

  configured_reviewers() {
    printf '%s\n' claude
  }

  models_for_reviewer() {
    printf '%s\n' default
  }

  run_review_attempt() {
    local actual_model_file="$6"
    printf '%s' 'claude-opus-4-7' > "$actual_model_file"
    cat <<'FIXTURE'
APPROVED

### Summary
Clean backup.
FIXTURE
    return 0
  }

  write_pr_body() {
    LAST_PR_BODY="$2"
  }

  upsert_review_diagnostics_comment() {
    LAST_DIAGNOSTICS_COMMENT="$2"
  }

  delete_review_diagnostics_comment() {
    DELETE_DIAGNOSTICS_CALLED=true
  }

  set +e
  review_pr "147" "https://github.com/example/repo/pull/147"
  local review_exit=$?
  set -e

  assert_eq "0" "$review_exit" "clean review_pr exit"
  assert_eq "APPROVED" "$(printf '%s\n' "$LAST_PR_BODY" | sed -n '1p')" "clean review body starts with approved"
  assert_eq "" "$LAST_DIAGNOSTICS_COMMENT" "clean success should not upsert diagnostics"
  assert_eq "true" "$DELETE_DIAGNOSTICS_CALLED" "clean success should delete stale diagnostics"
}

test_review_pr_reports_auxiliary_models_separately() {
  LAST_PR_BODY=""

  gh() {
    if [[ "$1" == "pr" && "$2" == "diff" ]]; then
      printf '%s\n' 'diff --git a/file b/file'
      return 0
    fi
    return 1
  }

  configured_reviewers() {
    printf '%s\n' claude
  }

  models_for_reviewer() {
    printf '%s\n' opus
  }

  run_review_attempt() {
    local actual_model_file="$6"
    local auxiliary_models_file="${8:-}"
    printf '%s' 'claude-opus-5' > "$actual_model_file"
    [[ -n "$auxiliary_models_file" ]] &&
      printf '%s' 'claude-haiku-4-5-20251001' > "$auxiliary_models_file"
    printf '%s\n' 'APPROVED' '' '### Summary' 'Clean backup.'
  }

  write_pr_body() {
    LAST_PR_BODY="$2"
  }

  upsert_review_diagnostics_comment() { :; }
  delete_review_diagnostics_comment() { :; }

  review_pr "267" "https://github.com/example/repo/pull/267"

  [[ "$LAST_PR_BODY" == *'Reviewed by **Claude** (model: `claude-opus-5`, configured: `opus`)'* ]] ||
    fail "Claude response model footer missing"
  [[ "$LAST_PR_BODY" == *'Auxiliary models: `claude-haiku-4-5-20251001`'* ]] ||
    fail "Claude auxiliary model footer missing"
}

source_helpers

test_toml_config_loader_validates_and_flattens_settings
test_missing_local_config_stops_before_backup
test_notification_self_test_runs_without_backup_config
test_setup_notification_click_copies_command
test_notification_denial_falls_back_to_osascript
test_notification_failure_is_written_to_stderr
test_deprecated_reviewer_flag_notifies_and_copies_migration_command
test_reviewer_flags_are_rejected_with_migration_guidance
test_install_requires_valid_local_config_before_side_effects
test_install_validates_inherited_opencode_go_key
test_preface_approved_is_normalized
test_preface_changes_requested_is_normalized
test_no_verdict_is_invalid
test_multiple_verdicts_are_invalid
test_correct_output_is_unchanged
test_claude_stream_reports_response_and_auxiliary_models
test_claude_stream_empty_result_uses_final_assistant_message
test_claude_review_uses_stream_response_model
test_claude_haiku_uses_thinking_toggle_instead_of_effort
test_codex_and_opencode_reviews_apply_configured_reasoning
test_sanitize_attempt_reason
test_sanitize_authorization_bearer
test_sanitize_claude_json_auth_error
test_auto_commit_stashes_untracked_work
test_run_backup_skips_refresh_when_dirty
test_noninteractive_runtime_finds_opencode_installer_binary
test_agy_review_uses_read_only_streaming_interface
test_agy_review_preserves_local_input_diagnostic
test_opencode_go_api_review_uses_separate_key_and_helper
test_autobackup_uses_nvm_default_for_npm_backup
test_review_prompt_blocks_wholesale_package_backup_deletions
test_review_pr_escapes_invalid_utf8_before_review
test_review_pr_skips_remaining_models_after_adapter_failure
test_review_pr_falls_back_and_writes_diagnostics
test_review_pr_deletes_stale_diagnostics_on_clean_success
test_review_pr_reports_auxiliary_models_separately

printf 'ok - auto-review helper tests passed\n'

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

source_helpers() {
  local stub_dir
  stub_dir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-review-test-stubs.XXXXXX")"
  printf '#!/usr/bin/env bash\n[[ "$1" == push ]] && exit 1\n/usr/bin/git "$@"\n' > "$stub_dir/git"
  chmod +x "$stub_dir/git"

  PATH="$stub_dir:$PATH" \
    DOTFILES_AUTOBACKUP_SOURCE_ONLY=true \
    DOTFILES_REPO_DIR="$REPO_DIR" \
    source "$SCRIPT_DIR/auto-commit.sh" --test
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

  grep -q '^npm ' "$REPO_DIR/apps/Brewfile" ||
    fail "Brewfile does not contain the npm globals returned by the default Node dump"
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

source_helpers

test_preface_approved_is_normalized
test_preface_changes_requested_is_normalized
test_no_verdict_is_invalid
test_multiple_verdicts_are_invalid
test_correct_output_is_unchanged
test_sanitize_attempt_reason
test_sanitize_authorization_bearer
test_sanitize_claude_json_auth_error
test_auto_commit_stashes_untracked_work
test_run_backup_skips_refresh_when_dirty
test_autobackup_uses_nvm_default_for_npm_backup
test_review_prompt_blocks_wholesale_package_backup_deletions
test_review_pr_falls_back_and_writes_diagnostics
test_review_pr_deletes_stale_diagnostics_on_clean_success

printf 'ok - auto-review helper tests passed\n'

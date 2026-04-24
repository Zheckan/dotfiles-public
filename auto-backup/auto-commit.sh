#!/usr/bin/env bash
# Auto-commit script — called by LaunchAgent or Apple Shortcut
# Sets up PATH for non-interactive environments (Shortcuts, launchd)

# Load Homebrew and user PATH
eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null)" || true
export PATH="$HOME/.nvm/versions/node/$(ls "$HOME/.nvm/versions/node/" 2>/dev/null | tail -1)/bin:$PATH" 2>/dev/null || true
export PATH="/usr/local/bin:$HOME/.local/bin:$PATH"

# ── Flags ─────────────────────────────────────────────────────────
# --main-pc    : Full flow — rebase, backup, review, PR, merge
# --pr-only    : Same as --main-pc but without merge
# --no-rebase  : Skip rebase on main (combinable with above)
# --no-review  : Skip Claude review (combinable with above)
# --test       : Test mode — stay on current branch, push, create PR, review (no backup, no merge)
MAIN_PC=false
PR_ONLY=false
NO_REBASE=false
NO_REVIEW=false
TEST_MODE=false
for arg in "$@"; do
  case "$arg" in
    --main-pc) MAIN_PC=true ;;
    --pr-only) PR_ONLY=true ;;
    --no-rebase) NO_REBASE=true ;;
    --no-review) NO_REVIEW=true ;;
    --test) TEST_MODE=true ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

# ── PR Review (Claude Code) ──────────────────────────────────────
# Reviews the PR diff using claude CLI before allowing merge.
# Posts the review as a PR comment. Returns 0 if approved, 1 otherwise.
review_pr() {
  local pr_number="$1"
  local pr_url="$2"

  # Check if claude CLI is available
  if ! command -v claude &>/dev/null; then
    gh pr edit "$pr_number" --body "> **Auto-review skipped**
\`claude\` CLI not found on this machine. Please review this backup manually before merging." > /dev/null 2>&1
    notify_error "claude CLI not available — PR #$pr_number left open" "$pr_url"
    return 1
  fi

  # Get the diff
  local diff
  diff=$(gh pr diff "$pr_number" 2>/dev/null)
  if [[ -z "$diff" ]]; then
    gh pr edit "$pr_number" --body "**Auto-review failed**: could not retrieve PR diff." > /dev/null 2>&1
    notify_error "Failed to get PR diff — PR #$pr_number left open" "$pr_url"
    return 1
  fi

  # Load review prompt
  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$DOTFILES_REPO_DIR")
  local prompt_file="$repo_root/.github/review-prompt.md"
  if [[ ! -f "$prompt_file" ]]; then
    gh pr edit "$pr_number" --body "**Auto-review skipped**: review prompt file not found." > /dev/null 2>&1
    notify_error "review-prompt.md missing — PR #$pr_number left open" "$pr_url"
    return 1
  fi

  local prompt
  prompt=$(cat "$prompt_file")

  # Parse model from .github/review-prompt.md
  local model
  model=$(grep -E '^model:\s*' "$prompt_file" | head -1 | sed 's/^model:\s*//' | xargs)

  # Model cascade: try each until one succeeds
  # If a specific model is pinned, only try that one (no fallback)
  local models_to_try=()
  local model_used="default"

  if [[ -n "$model" && "$model" != "default" ]]; then
    models_to_try=("$model")
  else
    # Auto cascade: default → sonnet → haiku
    models_to_try=("" "claude-sonnet-4-5-20250514" "claude-haiku-4-5-20251001")
  fi

  local review=""
  for try_model in "${models_to_try[@]}"; do
    local try_args=()
    local try_label="default"
    if [[ -n "$try_model" ]]; then
      try_args=(--model "$try_model")
      try_label="$try_model"
    fi

    local try_output
    # Try plain text output first; fall back to stream-json parsing
    # if result is empty (workaround for CLI bug where result field
    # is blank despite the model returning text content).
    try_output=$(printf '%s' "$diff" | claude -p "${try_args[@]}" "$prompt" 2>/dev/null)
    local try_exit=$?

    if [[ $try_exit -eq 0 && -z "$try_output" ]]; then
      # Plain text was empty — retry with stream-json and extract text blocks
      try_output=$(set -o pipefail; printf '%s' "$diff" \
        | claude -p "${try_args[@]}" --verbose --output-format stream-json "$prompt" 2>/dev/null \
        | python3 -c "
import sys, json
for raw in sys.stdin:
    raw = raw.strip()
    if not raw:
        continue
    try:
        event = json.loads(raw)
    except Exception:
        continue
    if event.get('type') != 'assistant':
        continue
    msg = event.get('message', {}) or {}
    for c in msg.get('content', []) or []:
        if c.get('type') == 'text':
            text = (c.get('text') or '').strip()
            if text:
                print(text)
" 2>/dev/null)
      try_exit=$?
    fi

    # Accept only if exit code is 0 AND output is non-empty
    if [[ $try_exit -eq 0 && -n "$try_output" ]]; then
      review="$try_output"
      model_used="$try_label"
      break
    fi
    echo "  ↳ $try_label failed (exit=$try_exit), trying next model..." >&2
  done

  if [[ -z "$review" ]]; then
    gh pr edit "$pr_number" --body "**Auto-review failed**: \`claude\` returned an empty response. Please review manually." > /dev/null 2>&1
    notify_error "Claude review empty — PR #$pr_number left open" "$pr_url"
    return 1
  fi

  # Append review metadata footer
  local review_with_footer="$review

---
> Reviewed by **Claude** (model: \`$model_used\`) via [Claude Code](https://claude.com/claude-code)"

  # Update PR body with the review (use temp file to handle special characters)
  local tmp_review
  tmp_review=$(mktemp)
  echo "$review_with_footer" > "$tmp_review"
  gh pr edit "$pr_number" --body-file "$tmp_review" > /dev/null 2>&1
  rm -f "$tmp_review"

  # Check verdict (first non-empty line)
  if echo "$review" | sed '/^[[:space:]]*$/d' | head -1 | grep -q "^APPROVED"; then
    return 0
  else
    notify_error "PR #$pr_number flagged by review — needs manual check" "$pr_url"
    return 1
  fi
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

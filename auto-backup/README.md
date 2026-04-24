# Auto-Backup

Automatically runs `backup.sh`, commits to a **device-specific branch**, and pushes on a schedule. Optionally merges to `main` via PR.

> **macOS only.** Device detection uses `system_profiler`, notifications use `terminal-notifier`/`osascript`, and scheduling uses LaunchAgent / Apple Shortcuts.

## Setup

Install `terminal-notifier` for clickable notifications (opens PR in browser on click):

```bash
brew install terminal-notifier
```

Without it, notifications fall back to `osascript` (no click-to-open).

## Device branches

Each device gets its own branch, auto-detected from hardware:

```
device/{model}-{serial-suffix}/{username}
device/{model}-{serial-suffix}/work
```

Branch name format: `device/{ModelName}-{SerialSuffix}/{username}`

The `device/` prefix separates backup branches from development branches (`feature/`, `fix/`), allowing different Copilot review rules per branch type.

The model name and serial are read from `system_profiler`. The branch is created automatically on first run.

## Environment

The scripts derive their repo path and GitHub URLs automatically, but these variables
can make the setup explicit:

```bash
export DOTFILES_REPO_DIR="$HOME/Developer/dotfiles"
export DOTFILES_GITHUB_REPO="your-user/your-private-dotfiles"
export DOTFILES_LOG_DIR="$HOME/Library/Logs/dotfiles"
export DOTFILES_AUTOBACKUP_LOCKFILE="/tmp/dotfiles-autocommit.lock"
```

Defaults:

| Variable | Default |
|---|---|
| `DOTFILES_REPO_DIR` | Git root or the parent directory of `auto-backup/` |
| `DOTFILES_GITHUB_REPO` | Parsed from `git remote get-url origin` |
| `DOTFILES_LOG_DIR` | `$HOME/Library/Logs/dotfiles` |
| `DOTFILES_AUTOBACKUP_LOCKFILE` | `/tmp/dotfiles-autocommit.lock` |

LaunchAgent and Apple Shortcuts run in non-interactive environments. If your setup
depends on custom values, embed them in the launcher command or load them explicitly
before calling `run-backup.sh`.

## Flags

| Flag | Description |
|---|---|
| *(none)* | Rebase, backup, commit & push to device branch |
| `--main-pc` | Full flow: rebase, backup, review, PR, merge to main |
| `--pr-only` | Same as `--main-pc` but without merge (review + PR only) |
| `--test` | Test mode: stay on current dev branch, push, create PR, review (no backup, no merge) |
| `--no-rebase` | Skip rebase on main. Combinable with any flag above |
| `--no-review` | Skip Claude review. Combinable with any flag above |

### What each step does

| Step | *(none)* | `--main-pc` | `--pr-only` | `--test` |
|------|----------|-------------|-------------|----------|
| Rebase on main | Yes | Yes | Yes | No |
| Run backup | Yes | Yes | Yes | No |
| Commit & push | Yes | Yes | Yes | No |
| Create/find PR | No | Yes | Yes | Yes |
| Claude review | No | Yes | Yes | Yes |
| Squash-merge | No | Yes | No | No |

```bash
# Default: rebase + backup + commit to device branch
"$DOTFILES_REPO_DIR/auto-backup/run-backup.sh"

# Main PC: full flow with review and merge
"$DOTFILES_REPO_DIR/auto-backup/run-backup.sh" --main-pc

# PR without merge: backup + review + PR (leaves PR open)
"$DOTFILES_REPO_DIR/auto-backup/run-backup.sh" --pr-only

# Test current dev branch: push, create PR, review (no backup/merge)
"$DOTFILES_REPO_DIR/auto-backup/run-backup.sh" --test

# Skip rebase (combinable)
"$DOTFILES_REPO_DIR/auto-backup/run-backup.sh" --main-pc --no-rebase

# Skip review (combinable)
"$DOTFILES_REPO_DIR/auto-backup/run-backup.sh" --main-pc --no-review

# PR without review
"$DOTFILES_REPO_DIR/auto-backup/run-backup.sh" --pr-only --no-review
```

**What `--main-pc` does:**
1. Rebases the device branch on latest `main`
2. Runs `backup.sh` to capture current configs
3. Creates a PR (or reuses an existing open one)
4. Reviews the PR diff with Claude Code (`claude -p`)
5. If approved → squash-merges the PR and resets device branch to `main`
6. If flagged → leaves PR open, posts review comment, sends notification

If anything fails (rebase conflict, push failure, PR error, review rejection), a macOS notification alerts you. Clicking the notification opens the PR in your browser (requires `terminal-notifier`). The backup remains safe on the device branch.

## PR Review

Before auto-merging, the script runs the PR diff through Claude Code for review. The review checks for:
- Accidentally committed secrets, tokens, or credentials
- Corrupted or empty config files
- Unexpected file deletions
- Security-sensitive changes (SSH, git, shell PATH)
- Large or unusual diffs that may indicate sync errors
- Unrecognized files outside known backup modules

The review is written into the **PR description** with a structured summary including a confidence level and risk table.

### Review config

The review prompt and model config live in `.github/review-prompt.md`:

```
model: default    ← auto cascade: default → sonnet → haiku
```

- `model: default` — tries your subscription's default model first, then automatically falls back through sonnet → haiku if it fails (e.g. token limits on large diffs)
- Pin a specific model with e.g. `model: claude-sonnet-4-5-20250514` — no fallback, only that model is tried

### Review flow

```
PR created → gh pr diff → claude -p (.github/review-prompt.md)
                                    ↓
                          APPROVED? → squash-merge
                          CHANGES_REQUESTED? → leave PR open + notify
                          error/empty? → cascade: sonnet → haiku
                                        all failed? → leave PR open + notify
```

## Option A: LaunchAgent (background, silent)

Runs every 2 days (172800 seconds) via macOS LaunchAgent. Commits to device branch only (no merge to main).

```bash
./install.sh        # Install and load the LaunchAgent
./uninstall.sh      # Remove it
```

Logs: `/tmp/dotfiles-autocommit.log`

## Option B: Apple Shortcut (visible, flexible scheduling)

Uses Shortcuts.app with a scheduled Automation. Easier to discover, edit, and toggle.

```bash
./install-shortcut.sh   # Guided setup
```

Or create manually:
1. Open **Shortcuts.app** → click **+**
2. Name it **Dotfiles Backup**
3. Add action: **Run Shell Script**
4. Shell: `/bin/bash`, script: `export DOTFILES_REPO_DIR="$HOME/Developer/dotfiles"; "$DOTFILES_REPO_DIR/auto-backup/run-backup.sh" --main-pc`
   (omit `--main-pc` if this is not your primary machine)
5. Go to **Automations** tab → **+** → **Time of Day**
6. Set schedule (e.g. daily at 2 AM, or every other day)
7. Action: **Run Shortcut** → select **Dotfiles Backup**
8. Toggle OFF **Ask Before Running**

You can also run it on demand:
```bash
shortcuts run "Dotfiles Backup"
```

## Which to choose?

| | LaunchAgent | Apple Shortcut |
|---|---|---|
| Runs silently | Yes | Depends on macOS version |
| Easy to toggle | `launchctl` commands | Toggle in Shortcuts.app |
| Flexible schedule | Fixed interval only | Any time/day/condition |
| Discoverable | Hidden in ~/Library | Visible in Shortcuts.app |
| Runs without login | Can be configured | No |
| Supports `--main-pc` | Not by default | Yes (add to script) |

## Files

| File | Purpose |
|---|---|
| `run-backup.sh` | **Entry point** — syncs repo with main, then exec's `auto-commit.sh`. Use this instead of calling `auto-commit.sh` directly |
| `auto-commit.sh` | Core logic: backup, commit, review, PR, merge. Called by `run-backup.sh` |
| `.github/review-prompt.md` | Review prompt shared by Claude, Copilot, and Codex (editable) |
| `install.sh` | Generate and load the LaunchAgent plist (Option A) |
| `uninstall.sh` | Remove the LaunchAgent (Option A) |
| `install-shortcut.sh` | Guided Apple Shortcut setup (Option B) |

### Why `run-backup.sh`?

`auto-commit.sh` updates itself via rebase, but bash already has the old version in memory.
`run-backup.sh` syncs the repo first, then `exec`s `auto-commit.sh` — so the latest code always runs.
The launcher is tiny and rarely changes, so this problem doesn't apply to it.

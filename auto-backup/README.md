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

## Config

Normal auto-backup behavior is configured in required `auto-backup/config.env`. This
private repo commits `main-pc` as the default mode there, so Shortcuts can call
`run-backup.sh` without mode flags. Machine-local overrides can go in ignored
`auto-backup/config.local.env`.

Precedence:

1. CLI flags for one run
2. `auto-backup/config.local.env`
3. `auto-backup/config.env` (required)

Key config values:

```bash
DOTFILES_AUTOBACKUP_MODE="main-pc"        # device-only | main-pc | pr-only | test
DOTFILES_AUTOBACKUP_REBASE="true"        # true | false
DOTFILES_AUTOBACKUP_REVIEW="true"        # true | false
DOTFILES_REVIEWERS="claude,codex,gemini" # comma-separated reviewer fallback order
DOTFILES_REVIEW_CLAUDE_MODELS="default,sonnet,haiku"
DOTFILES_REVIEW_CODEX_MODELS="default,gpt-5.4,gpt-5.4-mini"
DOTFILES_REVIEW_GEMINI_MODELS="default,gemini-3-flash-preview,flash"
```

The script validates mode, booleans, reviewer names, and non-empty model lists before
it runs backup, commit, PR, or merge work. Model names are passed through to each CLI
as best-effort strings because model availability changes outside this repo.

To generate a config interactively:

```bash
./auto-backup/configure.sh
```

The setup script uses arrow-key menus. For reviewers, Space selects one or more
providers, then the script asks for the default reviewer first and fallback reviewers
after that. Claude, Codex, and Gemini are tested adapters; OpenCode, Cursor, and
Ollama are experimental selectors that fail closed. The script writes
`auto-backup/config.env` and prints the Shortcuts shell snippet to use.

## Flags

| Flag | Description |
|---|---|
| *(none)* | Use `auto-backup/config.env` (`main-pc` in this private repo) |
| `--main-pc` | Full flow: rebase, backup, review, PR, merge to main |
| `--pr-only` | Same as `--main-pc` but without merge (review + PR only) |
| `--test` | Test mode: stay on current dev branch, push, create PR, review (no backup, no merge) |
| `--no-rebase` | Skip rebase on main. Combinable with any flag above |
| `--no-review` | Skip AI review. Combinable with any flag above |
| `--claude`, `--codex`, `--gemini` | Select AI reviewers in flag order |
| `--opencode`, `--cursor`, `--ollama` | Experimental reviewer selectors; fail closed until enabled/tested |

### What each step does

| Step | *(none)* | `--main-pc` | `--pr-only` | `--test` |
|------|----------|-------------|-------------|----------|
| Rebase on main | Configured | Yes | Yes | No |
| Run backup | Configured | Yes | Yes | No |
| Commit & push | Configured | Yes | Yes | No |
| Create/find PR | Configured | Yes | Yes | Yes |
| AI review | Configured | Yes | Yes | Yes |
| Squash-merge | Configured | Yes | No | No |

```bash
# Configured default from auto-backup/config.env
"$DOTFILES_REPO_DIR/auto-backup/run-backup.sh"

# Override config for one run: full flow with review and merge
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

# Review with Codex first, then Claude fallback
"$DOTFILES_REPO_DIR/auto-backup/run-backup.sh" --pr-only --codex --claude
```

**What `main-pc` mode does:**
1. Rebases the device branch on latest `main`
2. Runs `backup.sh` to capture current configs
3. Creates a PR (or reuses an existing open one)
4. Reviews the PR diff with the configured AI reviewer chain
5. If approved → squash-merges the PR and resets device branch to `main`
6. If flagged → leaves PR open, writes the review to the PR description, sends notification

If anything fails (rebase conflict, push failure, PR error, review rejection), a macOS notification alerts you. Clicking the notification opens the PR in your browser (requires `terminal-notifier`). The backup remains safe on the device branch.

## PR Review

Before auto-merging, the script runs the PR diff through an AI reviewer. The review checks for:
- Accidentally committed secrets, tokens, or credentials
- Corrupted or empty config files
- Unexpected file deletions
- Security-sensitive changes (SSH, git, shell PATH)
- Large or unusual diffs that may indicate sync errors
- Unrecognized files outside known backup modules

The review is written into the **PR description** with a structured summary including a confidence level and risk table.

### Review config

The review prompt lives in `.github/review-prompt.md`. Reviewer and model order lives
in `auto-backup/config.env`.

- `default` asks the CLI to use its configured/default model.
- Stable aliases like `sonnet` and `haiku` are preferred for unattended automation.
- Exact model IDs can be configured when you want pinning; if they disappear, the
  script tries the next configured model/reviewer and leaves the PR open if all fail.

Reviewer order can be set in either flags or environment:

```bash
# Flags win and preserve order
"$DOTFILES_REPO_DIR/auto-backup/run-backup.sh" --main-pc --codex --claude

# Or configure defaults in auto-backup/config.env
DOTFILES_REVIEWERS="codex,claude"
DOTFILES_REVIEW_CODEX_MODELS="default,gpt-5.4,gpt-5.4-mini"
DOTFILES_REVIEW_CLAUDE_MODELS="default,sonnet,haiku"
```

Supported reviewers:

| Reviewer | Status | Command used |
|---|---|---|
| Claude | Default, tested | `claude -p` |
| Codex | Tested | `codex exec --sandbox read-only` |
| Gemini | Tested | `gemini -o text` |
| OpenCode | Experimental, untested | Selector exists, but fails closed |
| Cursor | Experimental, untested | Selector exists, but fails closed |
| Ollama | Experimental, untested | Selector exists, but fails closed |

The PR body footer records which reviewer and model produced the review. Claude and
Gemini use model usage metadata from JSON output. Codex JSON output does not include
a resolved model field, so `default` is resolved from `~/.codex/config.toml` when
available; explicit Codex models are recorded directly.

### Review flow

```
PR created → gh pr diff → configured reviewer/model attempts
                                      ↓
                            APPROVED? → squash-merge
                            CHANGES_REQUESTED? → leave PR open + notify
                            error/empty? → try next model/reviewer
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
4. Shell: `/bin/bash`, script: `export DOTFILES_REPO_DIR="$HOME/Developer/dotfiles"; "$DOTFILES_REPO_DIR/auto-backup/run-backup.sh"`
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
| Supports `main-pc` mode | Configure plist/env | Yes (through `config.env`) |

## Files

| File | Purpose |
|---|---|
| `run-backup.sh` | **Entry point** — syncs repo with main, then exec's `auto-commit.sh`. Use this instead of calling `auto-commit.sh` directly |
| `auto-commit.sh` | Core logic: backup, commit, review, PR, merge. Called by `run-backup.sh` |
| `config.env` | Tracked defaults for mode, reviewer order, and model fallback |
| `configure.sh` | Interactive config setup that writes `config.env` and prints automation instructions |
| `.github/review-prompt.md` | Review prompt shared by AI review backends (editable) |
| `install.sh` | Generate and load the LaunchAgent plist (Option A) |
| `uninstall.sh` | Remove the LaunchAgent (Option A) |
| `install-shortcut.sh` | Guided Apple Shortcut setup (Option B) |

### Why `run-backup.sh`?

`auto-commit.sh` updates itself via rebase, but bash already has the old version in memory.
`run-backup.sh` syncs the repo first, then `exec`s `auto-commit.sh` — so the latest code always runs.
The launcher is tiny and rarely changes, so this problem doesn't apply to it.

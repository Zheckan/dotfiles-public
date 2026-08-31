# Auto-Backup

Automatically runs `backup.sh`, commits to a **device-specific branch**, and pushes on a schedule. Optionally merges to `main` via PR.

> **macOS only.** Device detection uses `system_profiler`, notifications use `terminal-notifier`/`osascript`, and scheduling uses LaunchAgent / Apple Shortcuts.

## Setup

Install `terminal-notifier` for clickable notifications (opens PR in browser on click):

```bash
brew install terminal-notifier
```

Without it, notifications fall back to `osascript` (no click-to-open).

Test notification delivery without running a backup or loading machine config:

```bash
./auto-backup/auto-commit.sh --test-notification
```

If no notification appears, enable notifications for `terminal-notifier` or
`osascript` in System Settings. Runtime delivery errors are also written to the
auto-backup log instead of being discarded.

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

Normal auto-backup behavior is configured in required, ignored
`auto-backup/config.local.toml`. There are no tracked machine defaults and no
reviewer-selection flags. Run setup before installing or running automation:

```bash
./auto-backup/configure.sh
```

Example:

```toml
[backup]
mode = "main-pc"
rebase = true

[review]
enabled = true
reviewers = ["agy", "opencode", "opencode-go-api"]

[review.models]
agy = ["gemini-3.7-flash-low"]
opencode = ["opencode/muse-spark-1.2-contributor-free"]
opencode-go-api = ["opencode-go/deepseek-v4-flash"]
```

The setup command launches a dependency-free Python terminal wizard. Mode choices
describe their complete backup/PR/merge behavior. Reviewer and model screens show
selection and fallback order together: Up/Down navigates, Space toggles, Left/Right
changes priority, Enter confirms, Esc goes back, and Q cancels without saving.
Claude, Codex, AGY, OpenCode CLI, and OpenCode Go direct API are tested adapters;
Cursor and Ollama are experimental selectors that fail closed.

For every selected reviewer, setup loads the models currently exposed by that CLI and
asks for the primary model followed by any fallbacks. AGY uses `agy models`, OpenCode
refreshes its provider-aware catalog with `opencode models --refresh`, and Codex uses
the machine-readable `codex debug models` catalog. Claude Code has no supported
machine-readable model-list command, so setup offers its stable aliases plus manual
entry. The Go API fetches `https://opencode.ai/zen/go/v1/models`. Selected IDs are
persisted; unattended backups do not refresh catalogs or change model order.

OpenCode CLI and OpenCode Go direct API are separate choices. The CLI reuses provider
credentials configured in OpenCode. The direct adapter sends the PR diff to documented
Go inference endpoints and needs the API key copied from OpenCode Zen. It prefers an
inherited `OPENCODE_GO_API_KEY`; otherwise setup validates and saves the key in ignored
`auto-backup/.env`. That file must have mode `0600`: only its owner can read or write
it. Installation revalidates the key with a small authenticated inference request.
The key is never added to the LaunchAgent plist.

Credential failures are classified rather than all being called invalid keys. The
credential screen always offers retry, remove OpenCode Go and continue, return to
model selection, or cancel setup. HTTP 403 can indicate account, subscription,
region, or edge restrictions and is not proof that the entered key is invalid.

Go is documented for internal agent use, but its terms prohibit programmatic output
extraction in broad language. Use this adapter only for your own internal reviews, not
for resale, scraping, multi-user proxying, or limit circumvention. Also review each
model's privacy terms: Muse Spark Contributor permits training on prompts and outputs.

## Flags

| Flag | Description |
|---|---|
| *(none)* | Use required `auto-backup/config.local.toml` |
| `--main-pc` | Full flow: rebase, backup, review, PR, merge to main |
| `--pr-only` | Same as `--main-pc` but without merge (review + PR only) |
| `--test` | Test mode: stay on current dev branch, push, create PR, review (no backup, no merge) |
| `--no-rebase` | Skip rebase on main. Combinable with any flag above |
| `--no-review` | Skip AI review. Combinable with any flag above |

Reviewer flags were removed. Use `configure.sh` to save reviewer and model fallback
order. A retired reviewer flag exits with migration guidance.

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
# Configured default from auto-backup/config.local.toml
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
in `auto-backup/config.local.toml`.

- `default` asks the CLI to use its configured/default model.
- Stable aliases `sonnet`, `fable`, `opus`, and `haiku` are available for unattended automation.
- Exact model IDs can be configured when you want pinning; if they disappear, the
  script tries the next configured model/reviewer and leaves the PR open if all fail.
- If a reviewer adds a harmless preface before a single `APPROVED` or
  `CHANGES_REQUESTED` line, the script repairs the PR body so the verdict is first.
- Fallback attempts and output repairs are recorded in one sticky PR diagnostics
  comment, which is updated on reruns and removed when no longer needed.

Supported reviewers:

| Reviewer | Status | Command used |
|---|---|---|
| Claude | Default, tested | `claude -p` |
| Codex | Tested | `codex exec --sandbox read-only` |
| AGY | Tested | `agy --input-format stream-json --output-format stream-json --mode plan --sandbox` |
| OpenCode CLI | Tested | `opencode run --format json --agent plan` |
| OpenCode Go direct API | Tested offline; requires Go key | `opencode_go.py` over documented HTTPS endpoints |
| Cursor | Experimental, untested | Selector exists, but fails closed |
| Ollama | Experimental, untested | Selector exists, but fails closed |

OpenCode runs under `--agent plan`, its built-in read-only agent, because the
default `build` agent is configured with `"*": "allow"` and could edit the repo it
is reviewing. This matches the read-only sandbox used for Codex.

The PR body footer records which reviewer and model produced the review. Claude uses
model usage metadata from JSON output. Codex JSON output does not include a resolved
model field, so `default` is resolved from `~/.codex/config.toml` when available;
explicit Codex models are recorded directly. AGY and OpenCode run events carry no
resolved model id, so explicit models are recorded as configured and `default` is
reported as `default`. The direct Go adapter records its explicit `opencode-go/...`
model ID.

### Review flow

```
PR created → gh pr diff → configured reviewer/model attempts
                                      ↓
                            APPROVED? → squash-merge
                            CHANGES_REQUESTED? → leave PR open + notify
                            error/empty/invalid? → try next model/reviewer
                            single misplaced verdict? → repair body + record diagnostic
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
| Supports `main-pc` mode | Yes, through `config.local.toml` | Yes |

## Files

| File | Purpose |
|---|---|
| `run-backup.sh` | **Entry point** — syncs repo with main, then exec's `auto-commit.sh`. Use this instead of calling `auto-commit.sh` directly |
| `auto-commit.sh` | Core logic: backup, commit, review, PR, merge. Called by `run-backup.sh` |
| `config.local.toml` | Required ignored machine configuration written by `configure.sh` |
| `config.example.toml` | Public-safe configuration shape example |
| `.env` | Optional ignored OpenCode Go API key; must be mode `0600` |
| `config.py` | Strict TOML validator and shell adapter |
| `configure.py` | Full-screen Python setup wizard |
| `opencode_go.py` | Dependency-free direct Go API/model/credential adapter |
| `configure.sh` | Stable shell entry point for `configure.py` |
| `.github/review-prompt.md` | Review prompt shared by AI review backends (editable) |
| `install.sh` | Generate and load the LaunchAgent plist (Option A) |
| `uninstall.sh` | Remove the LaunchAgent (Option A) |
| `install-shortcut.sh` | Guided Apple Shortcut setup (Option B) |

### Why `run-backup.sh`?

`auto-commit.sh` updates itself via rebase, but bash already has the old version in memory.
`run-backup.sh` syncs scripts only when the worktree is clean, then `exec`s
`auto-commit.sh`. If local tracked, staged, or untracked work exists, it skips the
script refresh so `auto-commit.sh` can stash that work before switching branches.
The launcher is tiny and rarely changes, so this problem doesn't apply to it.

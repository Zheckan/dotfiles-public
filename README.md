# Dotfiles Public Scripts

## Before You Clone And Read Further

- There is a 99% chance a better open-source solution already exists.
- This is a very specific nerd thing and you probably do not need it.
- This may not work for you or your machine. It is highly personal and probably too hardcoded.
- This may not support backup for what you need, but you have a template. Figure it out and submit a PR if you really need it.

This repository is a public scripts-only shell of my private macOS dotfiles repo.
Things are auto-backed up when I update or add new scripts, so be careful.

The scripts are personal and opinionated, but they can be useful as a reference or
as a starting point for your own macOS dotfiles workflow. **Read before running.**

## Current Status

- Backup scripts are the actively used path and are tested on my personal machine.
- Install/restore scripts exist, but they have not been tested on a new machine.
- The private configuration files these scripts normally manage are not included here.
- Some scripts assume specific macOS app locations and command-line tools.
- The shell module is for Zsh and Oh My Zsh. Other shells need their own module.

## Requirements

Required for the full workflow:

- macOS
- Bash
- Git
- Xcode Command Line Tools
- Homebrew

Optional tools used by specific modules:

- `gh` for GitHub PR automation
- `terminal-notifier` for clickable macOS notifications
- `jq`, `python3`, and `rsync` for config processing/syncing
- `mas` for Mac App Store app management through Homebrew Bundle
- `claude` plus an active Claude subscription/login for local PR review in the private auto-backup flow
- `code`, `cursor`, and app-specific CLIs for editor backups
- `npm`, `pnpm`, `pip`, and related language tools for package backups

## How It Works

- `backup.sh` runs module backup scripts and copies current machine/app state into
  the private repo.
- `install.sh` runs module install scripts and applies repo state back to a machine.
- `auto-backup/run-backup.sh` launches the auto-backup flow.
- `auto-backup/auto-commit.sh` backs up, commits to a device branch, and can open,
  review, and merge a PR in the private repo.

Auto-backup flags:

- no flag: rebase, run backup, commit, and push to a device branch
- `--main-pc`: backup, create/reuse PR, run Claude review, and squash-merge if approved
- `--pr-only`: backup, create/reuse PR, and run review without merging
- `--test`: push/review the current branch without backup or merge
- `--no-rebase`: skip rebasing on `main`
- `--no-review`: skip Claude review

The Claude review/auto-merge path requires `gh` auth, `claude` CLI auth, and a Claude
setup that can run `claude -p`. If that is not available, the PR stays open for manual
review.

## Auto-Backup Setup

There are three ways to use auto-backup.

Manual run:

```bash
./auto-backup/run-backup.sh
```

Primary-machine run with PR review and merge:

```bash
./auto-backup/run-backup.sh --main-pc
```

Install the LaunchAgent if you want a background schedule:

```bash
./auto-backup/install.sh
```

This writes `~/Library/LaunchAgents/com.dotfiles.autocommit.plist` and runs every two
days by default. Remove it with:

```bash
./auto-backup/uninstall.sh
```

Use Apple Shortcuts if you want a visible macOS automation instead:

```bash
./auto-backup/install-shortcut.sh
```

For non-interactive runners like LaunchAgent or Shortcuts, set at least
`DOTFILES_REPO_DIR` explicitly if the repo is not in the expected location:

```bash
export DOTFILES_REPO_DIR="$HOME/Developer/dotfiles"
```

For `--main-pc`, authenticate first:

```bash
gh auth login
claude
```

The script creates a device branch like `device/{model}-{serial-suffix}/{username}`,
pushes the backup commit there, creates or reuses a PR to `main`, asks Claude to
review the diff, and squash-merges only when the review starts with `APPROVED`.

Modules are organized by area:

- `apps/`: Homebrew apps and selected app config backup scripts
- `cli/`: shell, Git, SSH, and miscellaneous CLI setup scripts
- `languages/`: Node and Python setup/package backup scripts
- `macos/`: macOS `defaults` automation
- `fonts/`: font setup through Homebrew-managed casks
- `history/`: shell history backup script
- `auto-backup/`: scheduled backup and PR automation

## What Gets Backed Up Privately

The private repo can store local snapshots for Homebrew apps, shell files/history,
Git and SSH config, editor settings/extensions/profiles, AI tool settings, terminal
config, app config, Node/Python globals, and macOS defaults.

Those snapshots are intentionally excluded from this public mirror.

## Runtime Environment

The scripts can run with defaults, but these environment variables make the setup
explicit:

```bash
export DOTFILES_REPO_DIR="$HOME/Developer/dotfiles"
export DOTFILES_GITHUB_REPO="your-user/your-private-dotfiles"
export DOTFILES_LOG_DIR="$HOME/Library/Logs/dotfiles"
export DOTFILES_AUTOBACKUP_LOCKFILE="/tmp/dotfiles-autocommit.lock"
```

`DOTFILES_REPO_DIR` defaults to the Git root or script location. `DOTFILES_GITHUB_REPO`
defaults to the `origin` remote slug when it can be parsed.

LaunchAgent and Apple Shortcuts run in a non-interactive environment. If you use
them, set required environment variables inside the launcher or load them explicitly.

## Safety Notes

- Do not make a full private dotfiles repo public without filtering files and history.
- Review install scripts before running them; they may overwrite local config.
- Keep secrets, SSH config, tokens, app exports, and shell history private.
- Treat this repo as reference code unless you have adapted it to your machine.

## License And Small Fee

There is a small fee for using this content: donate to [Come Back Alive](https://savelife.in.ua/en/donate-en/). Donate anything. As [Max Shcherbyna](https://twitter.com/max_shcherbyna) said: "Donate is like a penis, there isn't small one."

This project is licensed under the MIT License - see the LICENSE file for details. Just don't be cunts, and do not support Russia's war against Ukraine.

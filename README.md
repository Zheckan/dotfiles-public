# Dotfiles Public Scripts

This repository is a public scripts-only shell of a private macOS dotfiles repo.
The private repo stores personal configuration snapshots; this public mirror keeps
only the reusable automation scripts and public-safe documentation.

The scripts are personal and opinionated, but they can be useful as a reference or
as a starting point for your own macOS dotfiles workflow. Read before running.

## Current Status

- Backup scripts are the actively used and tested path.
- Install/restore scripts exist, but they have not been fully tested end-to-end.
- The private configuration files these scripts normally manage are not included here.
- Some scripts assume specific macOS app locations and command-line tools.

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
- `claude` for local PR review in the private auto-backup flow
- `code`, `cursor`, and app-specific CLIs for editor backups
- `npm`, `pnpm`, `pip`, and related language tools for package backups

## How It Works

- `backup.sh` runs module backup scripts and copies current machine/app state into
  the private repo.
- `install.sh` runs module install scripts and applies repo state back to a machine.
- `auto-backup/run-backup.sh` launches the auto-backup flow.
- `auto-backup/auto-commit.sh` backs up, commits to a device branch, and can open,
  review, and merge a PR in the private repo.

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

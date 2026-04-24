# Git

Manages `.gitconfig` and `.gitignore_global`.

## Install

```bash
./install.sh
```

Copies `.gitconfig` and `.gitignore_global` to `$HOME`. The global gitignore is automatically active — `.gitconfig` already sets `core.excludesfile` to point to it.

## Backup

```bash
./backup.sh
```

## Work-Specific Config

See [templates/README.md](templates/README.md) for how to set up a separate git identity for work repos.

## Update Configs

Edit `~/.gitconfig` or `~/.gitignore_global`, then run `./backup.sh`.

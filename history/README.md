# History

Backs up and restores Zsh command history.

## Backup

```bash
./backup.sh
```

Saves the last 10,000 lines of `~/.zsh_history` into the repo.

## Install (Restore)

```bash
./install.sh
```

Overwrites `~/.zsh_history` with the backed-up version. Use with care -- this replaces your current history.

## Why 10,000 Lines?

The history file is truncated to the most recent 10,000 lines to keep the repo size manageable. Full Zsh history files can grow to hundreds of megabytes over time, which would bloat the git repository. 10,000 lines is enough to cover several months of active use.

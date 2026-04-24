# SSH

Manages the SSH `config` file. Private keys are never committed.

## Install

```bash
./install.sh
```

This script:

1. Creates `~/.ssh/` with correct permissions (`700`).
2. Copies `config` from the repo to `~/.ssh/config`.
3. Generates a new `ed25519` SSH key if one does not already exist.

## Backup

```bash
./backup.sh
```

Backs up `~/.ssh/config` only. Private keys are excluded by `.gitignore`.

## Manual Steps

After generating a new key:

1. Copy the public key: `cat ~/.ssh/id_ed25519.pub | pbcopy`
2. Add it to GitHub: https://github.com/settings/keys

## Update Configs

Edit `~/.ssh/config`, then run `./backup.sh`.

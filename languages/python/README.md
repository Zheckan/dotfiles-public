# Python

Manages the Conda configuration file (`.condarc`).

## Install

```bash
./install.sh
```

Copies `.condarc` to `$HOME`.

## Backup

```bash
./backup.sh
```

## Manual Steps

Conda is not installed by this script. Install Miniconda or Anaconda manually:

1. Download the official `.pkg` installer from https://docs.conda.io
2. Run the installer.
3. Restart your shell.

## Update Configs

Edit `~/.condarc`, then run `./backup.sh`.

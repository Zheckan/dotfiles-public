# Terminal

Manages the [Ghostty](https://ghostty.org) terminal emulator configuration.

## Config Path

```
~/Library/Application Support/com.mitchellh.ghostty/config
```

## Install

```bash
./install.sh
```

Copies `ghostty/config` from the repo to the Ghostty config directory.

## Backup

```bash
./ghostty/backup.sh
```

Copies the live Ghostty config back into the repo.

## Update Configs

Edit the Ghostty config file directly (either in the system location or in `ghostty/config` in this repo), then run backup or install as needed.

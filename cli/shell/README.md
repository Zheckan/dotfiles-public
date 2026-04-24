# Shell

Manages Zsh configuration, Oh My Zsh, plugins, and a custom theme.

## What Gets Installed

- **Oh My Zsh** -- installed from the official script if not already present.
- **Plugins** (cloned into `~/.oh-my-zsh/custom/plugins/`):
  - `zsh-autosuggestions` -- inline command suggestions from history.
  - `zsh-syntax-highlighting` -- real-time command syntax coloring.
  - `zsh-shift-select` -- shift+arrow text selection in the terminal.
- **Theme**: `theunraveler` -- copied into `~/.oh-my-zsh/custom/themes/`.
- **Dotfiles**: `.zshrc`, `.zshenv`, `.zprofile` -- copied to `$HOME`.

## Install

```bash
./install.sh
```

## Backup

```bash
./backup.sh
```

Copies `.zshrc`, `.zshenv`, `.zprofile`, and the `theunraveler.zsh-theme` from the system back into the repo.

## Update Configs

1. Edit the files in your home directory as usual.
2. Run `./backup.sh` to pull changes into the repo.
3. Commit.

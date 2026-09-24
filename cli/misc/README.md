# Misc

Manages configuration for various smaller tools.

## Install

```bash
./install.sh          # installs all misc configs
```

## Backup

```bash
./backup.sh
```

## Tools

| Subfolder | Config file | System path |
|---|---|---|
| `gh/` | `config.yml` | `~/.config/gh/config.yml` |
| `mise/` | `config.toml` | `~/.config/mise/config.toml` |
| `conda/` | `.condarc` | `~/.condarc` |
| `yarn/` | `.yarnrc.yml` | `~/.yarnrc.yml` |
| `mactop/` | `config.json` | `~/.mactop/config.json` |

## Manual Steps

- **gh CLI**: Run `gh auth login` to authenticate after install.
- **Raycast**: Backed up from its scheduled export. See `apps/raycast/README.md`.

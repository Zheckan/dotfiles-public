# Node

Manages Node.js runtime tooling and package-manager config.

Global npm packages are managed by Homebrew Bundle through
[`../../apps/Brewfile`](../../apps/Brewfile). `apps/backup.sh` captures them as
`npm "..."` entries, and `apps/install.sh` restores them with `brew bundle`.

## Install

```bash
./install.sh          # runs all sub-installers
```

Or individually:

```bash
./nvm/install.sh
./bun/install.sh
./yarn/install.sh
```

## Install Methods

| Tool | Method |
|---|---|
| **nvm** | Official install script via `curl` |
| **Bun** | `brew install bun` |
| **pnpm** | Installed from `apps/Brewfile` via Homebrew |
| **Yarn config** | Restored by `yarn/install.sh` |
| **Global npm packages** | Installed from `apps/Brewfile` via `brew bundle` |

## Backup

Global npm packages are backed up as part of `../../apps/backup.sh`.

## Update

After installing a new global npm package, run `../../apps/backup.sh` to update
the Brewfile. After installing nvm, restart your shell and run `nvm install --lts`.

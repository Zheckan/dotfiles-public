# Node

Manages the Node.js ecosystem: nvm, Bun, pnpm, and global npm packages.

## Install

```bash
./install.sh          # runs all sub-installers
```

Or individually:

```bash
./nvm/install.sh
./bun/install.sh
./pnpm/install.sh
./globals/install.sh
```

## Install Methods

| Tool | Method |
|---|---|
| **nvm** | Official install script via `curl` |
| **Bun** | `brew install bun` |
| **pnpm** | Standalone install script via `curl` |
| **Global packages** | Installed from `globals/npm-globals.txt` via `npm install -g` |

## Backup

```bash
# Export global packages list
./globals/backup.sh
```

This writes all globally installed npm and pnpm packages to `globals/npm-globals.txt`.

## Update

After installing a new global package, run `./globals/backup.sh` to update the list. After installing nvm, restart your shell and run `nvm install --lts`.

# Editors

Manages settings and extensions for Cursor, VS Code, and Zed.

## Install

```bash
./install.sh          # installs all three editors' configs
```

Or run each editor independently:

```bash
./cursor/install.sh
./vscode/install.sh
./zed/install.sh
```

## Backup

```bash
./backup.sh           # backs up all three
```

## What Each Editor Manages

| Editor | Files | Extensions |
|---|---|---|
| **Cursor** | `settings.json`, `keybindings.json`, `mcp.json`, `argv.json`, `snippets/`, `profiles/` (per-profile `settings.json`, `extensions.json`, `snippets/`), `globalStorage/storage.json` (profile metadata) | Default profile exported/imported via `cursor --install-extension` from `extensions.txt`; per-profile extensions listed in `profiles/<id>/extensions.json` |
| **VS Code** | `settings.json`, `keybindings.json`, `mcp.json`, `argv.json`, `snippets/`, `profiles/` (per-profile `settings.json`, `extensions.json`, `snippets/`), `globalStorage/storage.json` (profile metadata) | Default profile exported/imported via `code --install-extension` from `extensions.txt`; per-profile extensions listed in `profiles/<id>/extensions.json` |
| **Zed** | `settings.json` | Managed within Zed directly |

> **Profile runtime state excluded:** `profiles/<id>/globalStorage/`, `workspaceStorage/`, `History/`, `logs/`, `CachedData/`, `Backups/` are SQLite state DBs and caches — device-local and not versioned.
>
> **`globalStorage/storage.json` restore:** contains the `userDataProfiles` name→directory mapping plus device-specific telemetry IDs. `install.sh` does *not* overwrite it automatically; inspect and copy manually on a fresh machine.

## Update Configs

1. Change settings in the editor as usual.
2. Run `./backup.sh` to pull the latest configs into the repo.
3. To update the extensions list, the backup script exports currently installed extensions to `extensions.txt`.

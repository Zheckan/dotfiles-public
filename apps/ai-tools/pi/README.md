# Pi

The backup stores reusable user configuration from `~/.pi/agent/` under `config/`.
Set Pi's standard `PI_CODING_AGENT_DIR` environment variable to use another agent
directory. The master `backup.sh` invokes this module, so scheduled backups include
Pi without a new auto-backup setting.

## Backup

```bash
./backup.sh
./test-pi-backup.sh
```

`backup.sh` handles prerequisites, temporary staging, logging, and the final rsync.
`prepare-backup.py` prepares the allowlisted files and parses JSON for credential
redaction. This shell/Python split also exists in the Codex and OpenCode modules.
The Pi helper prepares a whole snapshot, rather than sanitizing only one file,
so it also checks resource exclusions, symlinks, and recognizable secret patterns.

The Bash tests exercise the backup command with isolated home/repo fixtures.
They require `jq` for JSON assertions, plus the backup's `python3` and `rsync`
dependencies. They never run the installer. Repeated-backup tests compare file
contents, not mtimes, because macOS openrsync and GNU rsync handle timestamp
updates differently.

Captured when present:

- `settings.json`, `keybindings.json`, `models.json`, and `mcp.json`.
- `AGENTS.override.md`, `AGENTS.md`, `AGENTS.MD`, `CLAUDE.md`, and `CLAUDE.MD`.
- `SYSTEM.md` and `APPEND_SYSTEM.md`.
- `extensions/`, `skills/`, `prompts/`, `themes/`, and custom resource `tests/`,
  including supporting files, package manifests, and lockfiles.

JSON backups replace inline credential values with
`REDACTED_SET_THIS_SECRET_ON_RESTORE`. Model/MCP keys, OAuth secrets, environment
values, headers, credential arguments, and HTTP URL credentials are handled.
Literal environment references such as `${TOOLS_KEY}` and `Bearer ${TOOLS_KEY}`
are retained. Credential commands are redacted rather than copied blindly.
`deviceId` and `lastChangelogVersion` are omitted from settings.

The entire snapshot is prepared before it is updated. Invalid JSON, missing
Python, unreadable resources, resource symlinks, or recognizable tokens/private
keys in custom source files cause a nonzero exit and leave the previous snapshot
unchanged. Resource symlinks are not followed into potentially private files.
Keep shared skills in `~/.agents/skills/`; Pi discovers them automatically and the
existing `agents/` module already backs them up. Review custom source and assets
for credentials; token detection cannot identify every possible secret format.

Excluded: credentials (`auth.json`, `mcp-auth.json`), sessions, trust decisions,
model catalog caches, CLI binaries, managed installs, downloaded packages,
temporary backups, `.env` files, `.git`, dependency trees, and Python caches.
Project `.pi/` directories belong in their respective project repositories.

Settings can refer to resources or local packages outside the captured directories.
The backup warns about these entries. Their source must be backed up separately;
saving a path does not save its target.
Downloaded npm/git packages are recreated from the declarations in settings.

## Restore

```bash
./install.sh
```

Installs the CLI through the [official installer](https://pi.dev/install.sh) only
if `pi` is missing. Existing managed installs in the agent directory and
`~/.local/bin` are found even if those paths were not initially on `PATH`.
The installer may ask for confirmation in an interactive terminal; it does not
start Pi before configuration is restored.

Restore is additive, with no `rsync --delete`. Existing local resources,
credentials, sessions, downloaded packages, and dependencies remain intact.
Replaced files are saved in `<agent-dir>/.dotfiles-restore-backups/restore.*`.

After restore:

- Run Pi's `/login`; use `/mcp login <server>` for MCP OAuth.
- Supply credentials removed from JSON and export referenced environment variables.
- Run `pi update --extensions` to reinstall configured npm/git packages.
- Install dependencies for local custom resources with package manifests.
- Approve project trust again on the new machine.

Sources checked against Pi 1.0.0: `docs/configuration.md`, `settings.md`,
`packages.md`, `skills.md`, `models.md`, `mcp.md`, and `security.md` in the installed
Pi package.

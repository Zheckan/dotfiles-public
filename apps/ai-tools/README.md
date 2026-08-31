# AI Tools

Manages shared agent skills and configuration for AI coding assistants: Claude Code, Codex, Antigravity, OpenCode, and T3 Code.

## Install

```bash
./install.sh          # installs all AI tool configs
```

Or individually:

```bash
./agents/install.sh
./claude/install.sh
./codex/install.sh
./antigravity/install.sh
./opencode/install.sh
./t3code/install.sh
```

## Backup

```bash
./backup.sh
```

## Tools

| Tool | Config Location | Notes |
|---|---|---|
| **Shared agent skills** | `~/.agents/` | Skill lock file and installed skills shared by compatible agent tools. |
| **Claude Code** | `~/.claude/` | Settings, keybindings, statusline script. Installed via `brew install --cask claude-code`. |
| **Codex** | `~/.codex/` | Config, rules, custom agents, user skills, and custom pets. Inline MCP credentials in `config.toml` are redacted to a placeholder on backup. Install with `npm install -g @openai/codex`. |
| **Antigravity** | `~/.gemini/antigravity-cli/`, `~/.gemini/config/skills.json`, `~/.antigravity/` | CLI settings and keybindings, app and CLI discovery paths pointing to `~/.agents/skills`, and statusline support scripts. Per-session state is excluded. Binary installed via `curl -fsSL https://antigravity.google/cli/install.sh \| bash`. |
| **OpenCode** | `~/.config/opencode/` | `opencode.json` plus `instructions/` directory. Inline MCP credentials are rewritten to `{env:NAME}` references on backup. `package.json`/`bun.lock` are not backed up — OpenCode's own `.gitignore` treats them as generated. |
| **T3 Code** | `~/.t3/userdata/` | Client settings, app settings, and keybindings. Runtime state is excluded. |

## Manual Steps

Each tool requires authentication after install:

- **Claude Code**: Run `claude` once to authenticate.
- **Codex**: Set your OpenAI API key.
- **Antigravity**: Run `agy` to authenticate with Google.
- **OpenCode**: See https://opencode.ai for setup instructions. Export any credentials
  the restored `opencode.json` references as `{env:NAME}`; `install.sh` lists them.
- **T3 Code**: Launch T3 Code once to regenerate runtime state.

## Credential handling

`codex/sanitize-config.py` and `opencode/sanitize-config.py` strip inline auth material
before it reaches the repo. Both backups fail closed: if the sanitizer cannot run, the
config is left at its previous committed state rather than copied through unsanitized.
Restoring raises a manual step naming the values you need to supply.

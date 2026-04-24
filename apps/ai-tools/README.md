# AI Tools

Manages configuration for AI coding assistants: Claude Code, Codex, Gemini CLI, and OpenCode.

## Install

```bash
./install.sh          # installs all AI tool configs
```

Or individually:

```bash
./claude/install.sh
./codex/install.sh
./gemini/install.sh
./opencode/install.sh
```

## Backup

```bash
./backup.sh
```

## Tools

| Tool | Config Location | Notes |
|---|---|---|
| **Claude Code** | `~/.claude/` | Settings, keybindings, statusline script. Installed via `brew install --cask claude-code`. |
| **Codex** | `~/.codex/` | `config.json`. Install with `npm install -g @openai/codex`. |
| **Gemini CLI** | `~/.gemini/` | `settings.json`. |
| **OpenCode** | `~/.config/opencode/` | `opencode.json` plus `instructions/` directory. |

## Manual Steps

Each tool requires authentication after install:

- **Claude Code**: Run `claude` once to authenticate.
- **Codex**: Set your OpenAI API key.
- **Gemini CLI**: Run `gemini` to authenticate with Google.
- **OpenCode**: See https://opencode.ai for setup instructions.

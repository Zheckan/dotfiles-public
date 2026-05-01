# AI Tools

Manages configuration for AI coding assistants: Claude Code, Codex, Gemini CLI, OpenCode, and T3 Code.

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
./t3code/install.sh
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
| **Gemini CLI** | `~/.gemini/` | Settings, `GEMINI.md`, commands, policies, and skills. Auth, project trust files, and runtime state are excluded. |
| **OpenCode** | `~/.config/opencode/` | `opencode.json` plus `instructions/` directory. |
| **T3 Code** | `~/.t3/userdata/` | Client settings, app settings, and keybindings. Runtime state is excluded. |

## Manual Steps

Each tool requires authentication after install:

- **Claude Code**: Run `claude` once to authenticate.
- **Codex**: Set your OpenAI API key.
- **Gemini CLI**: Run `gemini` to authenticate with Google.
- **OpenCode**: See https://opencode.ai for setup instructions.
- **T3 Code**: Launch T3 Code once to regenerate runtime state.

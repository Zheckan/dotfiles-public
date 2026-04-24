# Apps

Manages all applications via Homebrew formulae, casks, and Mac App Store (`mas`).

## Install

```bash
./install.sh          # runs: brew bundle --file=Brewfile
```

This installs everything: CLI tools, desktop apps, Mac App Store apps, and VS Code extensions.

## Update the Brewfile

```bash
./backup.sh           # runs: brew bundle dump --force --file=Brewfile
```

This overwrites the existing Brewfile with everything currently installed via Homebrew.
After dumping, it also scans `/Applications` for untracked apps and writes `untracked-apps.txt`.

## What's Included

| Category | Apps |
|----------|------|
| Browsers | Firefox, Google Chrome, Google Chrome Canary, Google Chrome Dev, Zen (manual) |
| AI Tools | ChatGPT, Claude, Codex, LM Studio, Ollama |
| Dev Tools | Cursor, DBeaver, Docker, Ghostty, Postman, Studio 3T, VS Code, Zed |
| Communication | Discord, Slack, Telegram, WhatsApp |
| Productivity | Figma, Linear, Notion, Notion Calendar, Obsidian, Spotify |
| Utilities | AnyDesk, AppCleaner, CodexBar, Helium, Logi Options+, MiddleClick, MultiViewer, Raycast |
| Office | Microsoft Word, Excel, PowerPoint |
| 3D / Maker | Bambu Studio, Blender |
| Gaming | CrossOver, Steam |
| Mac App Store | AdBlock Pro, ClearVPN, Developer, Folder Preview, Goodnotes, Keynote, Markdown Preview, Numbers, Pages, Simplenote, Windows App, Xcode |

## Manual Install Apps

These apps have no Homebrew cask and must be installed manually:

- **Zen Browser** — [zen-browser.app](https://zen-browser.app)
- **FPV LOGIC** — [fpvlogic.com](https://fpvlogic.com) (FPV drone configurator)

Not tracked by choice:

- **FileZilla** — no official cask
- **Zoom** — excluded per user preference
- **OpenVPN Connect** — excluded per user preference
- **Microsoft Teams** — excluded per user preference

## Manual Steps After Install

- Sign into Mac App Store apps (Goodnotes, Xcode, etc.)
- Sign into Microsoft Office (Word, Excel, PowerPoint)
- Sign into communication apps (Slack, Discord, Telegram, WhatsApp)
- Sign into Spotify, Notion, Obsidian, Figma, Linear
- Activate CrossOver license
- Install **FPV LOGIC** and **Zen Browser** manually (not available via Homebrew)
- Configure Logi Options+ for your peripherals
- Review Brewfile and remove unwanted apps before running on a new machine
- Fonts are also installed through cask entries in this Brewfile (see `fonts/`)

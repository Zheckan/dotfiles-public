# macOS

Manages macOS system preferences via `defaults write` commands.

## Install

```bash
./install.sh
```

This sources `defaults.sh`, which applies all settings and restarts affected processes (Dock, Finder, SystemUIServer).

## What It Configures

**Dock**
- Auto-hide enabled with no delay.
- Tile size 43, magnification on (large size 30).
- Minimize to application. Disable recent space reordering.

**Hot Corners** (all require Option modifier)
- Top-left: Launchpad. Top-right: Quick Note.
- Bottom-left: Mission Control. Bottom-right: Desktop.

**Finder**
- Show hidden files, path bar, status bar.
- List view by default. Search current folder.
- Folders sorted first. No extension change warning.
- New windows open to `~/Downloads/`.

**Keyboard**
- Fast key repeat (2) and short initial delay (25).
- Disable auto-capitalization, auto-correct, and period substitution.

**Trackpad**
- Tap to click enabled.

**Window Manager**
- Disable tiled window margins. Disable Stage Manager.

**Screenshots**
- Format set to PNG.

**Keyboard Shortcuts**
- Cmd+Shift+S for screenshot area to clipboard.
- Desktop/Spaces switching shortcuts (keys 15-26) disabled.

## Backup

```bash
./backup.sh
```

The backup does three things automatically:

1. **Shell history discovery** — scans `~/.zsh_history` for any `defaults write` commands and adds new ones to `defaults.sh`
2. **Domain monitoring** — scans Dock, Window Manager, Screenshot, and Trackpad domains for settings changed via System Preferences (GUI) and adds new ones to `defaults.sh`
3. **Value sync** — updates all existing settings in `defaults.sh` to match current system values
4. **Snapshot** — writes `defaults-snapshot.txt` for human-readable git diffs

This means if you change a setting via System Preferences or the command line, the next backup captures it automatically.

## Important

- Review `defaults.sh` before running on a new machine. Adjust values to your preference.
- Some changes require logout or restart to take effect.

Audit the system for apps, configs, and packages that are NOT currently tracked by the dotfiles repo.

## Instructions

Run the following checks and report findings in clear tables.

### 1. New Apps Not in Brewfile

Compare installed apps against the Brewfile at `apps/Brewfile`:

- List all apps in `/Applications/` and `~/Applications/` that do NOT have a matching `cask` entry in the Brewfile
- For each missing app, check if a brew cask exists (`brew search --cask "<name>"`) and suggest the cask name
- List any newly installed brew formulae (`brew leaves`) not in the Brewfile
- List any Mac App Store apps (`mas list`) not in the Brewfile

### 2. Config Files Not Being Backed Up

Check for config files that exist on the system but aren't copied by any `backup.sh` script:

- Scan `~/.config/` for directories not tracked by the repo
- Check for new dotfiles in `~/` (starting with `.`) — ignore transient files (.zcompdump, .zsh_sessions, .cache, .npm, .node_repl_history, .DS_Store, .Trash, .viminfo)
- Check `~/.claude/` for new files (plugins, commands, agents, etc.)
- Check `~/.cursor/` for new files beyond mcp.json
- Check `~/.config/gh/`, `~/.config/zed/`, `~/.config/opencode/` for new files

### 3. Package Manager Globals

Check ALL package managers for globally installed packages not tracked:

**npm/Node:**
- `npm list -g --depth=0` — compare with `languages/node/globals/npm-globals.txt` (note: scoped packages use `@scope/name` format)
- `pnpm list -g` if available
- `bun pm ls -g` if available

**Python/pip:**
- `pip list` — compare with `languages/python/globals/pip-globals.txt`
- Focus on user-installed CLI tools, ignore Anaconda-bundled packages (numpy, scipy, pandas, etc.)
- Flag tools like asitop, mypy, flake8, black, etc. that a developer would want on a new machine

**Ruby:**
- `gem list` if ruby is available — flag any user-installed gems

**Rust:**
- `cargo install --list` if cargo is available — flag any installed tools

**Go:**
- Check `~/go/bin/` for any installed Go binaries

### 4. VS Code / Cursor Extensions

- Compare `code --list-extensions` with `apps/editors/vscode/extensions.txt`
- Compare `cursor --list-extensions` with `apps/editors/cursor/extensions.txt`

### 5. Brew Services

- Run `brew services list` — flag any running services that should be noted

## Output Format

For each section, output a table with:
- What was found
- Whether it can be automated (brew cask name, mas ID, package manager command, config path)
- Suggested action (add to Brewfile, add to globals file, add backup script, ignore)

At the end, summarize:
- Total new items found
- Items that can be added automatically
- Items requiring manual action

If you find new items that should be tracked, ask the user if they want you to add them to the appropriate files (Brewfile, backup scripts, globals lists, etc.).

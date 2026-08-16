# Agents Instructions

This is a macOS dotfiles repository that backs up and restores system configuration files.

## Review guidelines

### For auto-backup PRs (from `device/*` branches)

Follow the review instructions in `.github/review-prompt.md`.

These PRs contain auto-generated config files copied verbatim from applications.
Do NOT suggest changes to file content — apps generate these files and any changes
would be overwritten on the next backup. Only flag actually dangerous changes:
leaked secrets, corrupted files, or unexpected deletions.

Treat wholesale loss of a package-manager backup section as an unexpected deletion.
For example, if all `npm` entries disappear from `apps/Brewfile`, the review must
return `CHANGES_REQUESTED` for human verification instead of approving with a warning.

### For development PRs (feature/fix branches)

For Claude Code: when available, use the `superpowers:requesting-code-review` skill
to dispatch the code-reviewer agent. Otherwise, follow the review rules below directly.

Review shell scripts for:
- Command injection or unsafe eval/exec
- Unquoted variables causing word splitting or glob expansion
- Missing error handling on commands that modify system state
- Credentials, tokens, or personal identifiers in code
- Logic that silently overwrites user configuration without backup
- Backup modules that are never invoked by the master `backup.sh`
- Modules wired into `install.sh` but not `backup.sh` (restore destroys live data)
- Inline credentials in app config that gets copied verbatim into the repo
- Sanitizers that fall back to copying a file through unsanitized on failure
- New `DOTFILES_*` config keys missing from the scripts that generate configs

Do NOT comment on: style, formatting, minor naming, or refactoring suggestions.

Use the Greptile-style review format:

```
### Summary
<one-paragraph overview>

### Confidence Score: X/5
<score with 1-2 sentence explanation>

### Important Files Changed
| Filename | Score | Overview |
|----------|-------|----------|
| (path)   | X/5   | Brief description and risk assessment |

X files reviewed, N comments

### Potential risks
<any risks or "None identified.">

### Issues
<any issues or "None identified.">
```

## Repository-specific pitfalls

Failure modes this repository's layout invites. Check them explicitly.

### Master `backup.sh` does not call the group orchestrators

`backup.sh` enumerates leaf modules directly. It never calls
`apps/ai-tools/backup.sh`, `apps/editors/backup.sh`, or `cli/misc/backup.sh`, so
wiring a module only into its orchestrator means the module never runs. Run
`./test-backup-coverage.sh` after adding a module — it derives the list from the
filesystem and fails on anything unreachable from the master script.

### Backup and restore must be wired symmetrically

`install.sh` *does* delegate to the group orchestrators, so a module can be fully
restorable while never being backed up. That asymmetry is destructive, not merely
stale: `sync_dir_to_system` uses `rsync --delete`, so restoring from a repo copy
that was never updated deletes live files. Anything added to `install.sh` must be
added to `backup.sh` in the same change.

### `.gitignore` does not protect config that must be backed up

`.gitignore` excludes whole files, which is no help when a config worth keeping
carries an inline secret — an MCP block or CLI argument can hold an API key in a
file that genuinely needs backing up. Those backups pipe through a sanitizer
(`apps/ai-tools/*/sanitize-config.py`) and must **fail closed** — on sanitizer
failure or missing `python3`, keep the previous committed copy and exit non-zero
rather than copying the file through. The matching `install.sh` raises a
`log_manual` step naming the values to restore.

### Config keys have generators that also need updating

Adding a `DOTFILES_*` key means updating all of: `auto-backup/config.env`,
`auto-backup/configure.sh` (both the prompt and `write_config`), and
`.opensource/scripts/export-public.sh` (which generates the public mirror's
config). Skipping a generator leaves the feature silently unconfigured for anyone
who regenerates their config.

### Assert the property that matters, not an intermediate link

A test asserting that a module is wired into its group orchestrator stays green
even while that module is never backed up, because nothing checks that the master
script reaches it. Assert the end-to-end property instead.

## Coding guidelines

- Shell scripts use Bash. Scripts sourcing `_helpers.sh` get `set -euo pipefail`; standalone scripts (like `auto-commit.sh`) handle errors explicitly
- Prefer `$HOME` or relative paths over hardcoded absolute paths in scripts (not in config files — those are app-generated)
- Install/backup scripts must be idempotent
- Never commit secrets, tokens, passwords, or private keys

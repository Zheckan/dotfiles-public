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

## Coding guidelines

- Shell scripts use Bash. Scripts sourcing `_helpers.sh` get `set -euo pipefail`; standalone scripts (like `auto-commit.sh`) handle errors explicitly
- Prefer `$HOME` or relative paths over hardcoded absolute paths in scripts (not in config files — those are app-generated)
- Install/backup scripts must be idempotent
- Never commit secrets, tokens, passwords, or private keys

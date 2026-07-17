---
applyTo: "**/*.sh,auto-backup/**"
excludeAgent: "coding-agent"
---

# Shell Script Review

## Must flag

- Command injection or unsafe eval/exec
- Unquoted variables that could cause word splitting or glob expansion
- Missing error handling on commands that modify system state
- Credentials, tokens, or personal identifiers in code
- Logic that silently overwrites user configuration without backup
- Race conditions (e.g., lockfile handling issues)

## Worth noting

- Commands that can fail but aren't checked (missing `|| true` or `set -e`)
- Hardcoded absolute paths (prefer `$HOME` or relative paths)
- Inconsistencies between script behavior and README documentation

## Skip

- Style preferences and formatting
- Minor naming suggestions
- Adding comments or documentation
- Refactoring that doesn't fix a bug

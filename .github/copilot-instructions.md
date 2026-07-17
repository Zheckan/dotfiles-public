This is a macOS dotfiles repository that backs up and restores system configuration files.

- Shell scripts use Bash. Check for safe quoting, error handling, and POSIX compatibility.
- Never commit secrets, tokens, passwords, or private keys.
- Install/backup scripts must be idempotent — running twice should not break the system.
- Prefer `$HOME` or relative paths over hardcoded absolute paths.

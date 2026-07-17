---
applyTo: "history/**,apps/Brewfile,apps/editors/**,apps/ai-tools/**,apps/multiviewer/**,apps/terminal/**,cli/shell/**,cli/git/**,cli/ssh/**,cli/misc/**,languages/**,macos/**,fonts/**"
---

Follow the review instructions in `.github/review-prompt.md`.

These are auto-generated config files copied verbatim from applications, NOT hand-written code.
Do NOT suggest changing hardcoded paths, refactoring JSON/YAML, or code style improvements.
Apps generate these files and any changes would be overwritten on the next backup.

Only comment on **critical issues**: leaked secrets, corrupted files, or unexpected deletions.
Treat wholesale loss of a package-manager backup section as an unexpected deletion.
For example, if all `npm` entries disappear from `apps/Brewfile`, return
`CHANGES_REQUESTED` for human verification instead of approving with a warning.
If everything looks safe, approve silently.

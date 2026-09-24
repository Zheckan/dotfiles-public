# Raycast

Raycast settings are managed via its built-in export/import feature, not through config files.

| Repo file | Source |
|---|---|
| `Raycast.rayconfig` | Newest `*.rayconfig` in `~/Library/Application Support/dotfiles/raycast-exports/` |

## Export Settings

Raycast's scheduled export must save into
`~/Library/Application Support/dotfiles/raycast-exports/`, **not** into this repo.
`backup.sh` copies the newest export from there to `Raycast.rayconfig`, so it is
committed on the device branch like every other module.

Exporting into the repo leaves an untracked file in whatever branch is checked out.
Auto-backup stashes untracked files before switching to the device branch, so such an
export would never be committed.

1. Open Raycast.
2. Go to **Settings** (Cmd+,) > **Advanced** > **Export**.
3. Protect the export with a password — it can contain extension preferences such as API keys.
4. Set the scheduled export location to the folder above (Cmd+Shift+G in the file picker to reach `~/Library`).

`install.sh` creates the folder on a new machine.

## Import Settings

1. Open Raycast.
2. Go to **Settings** > **Advanced** > **Import**.
3. Select `Raycast.rayconfig` from this directory and enter the export password.

Older exports are in git history (`git log -- apps/raycast/`).

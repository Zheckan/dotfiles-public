# Fonts

Two paths feed `~/Library/Fonts/`:

1. **Homebrew casks** (reproducible, no binaries in the repo). Declared in
   [`apps/Brewfile`](../apps/Brewfile) and installed by `apps/install.sh`.
2. **User backup** (for fonts with no cask equivalent, e.g. proprietary or
   hand-dropped files). TTF/OTF files live under `fonts/user/` and are
   restored by `fonts/install.sh`.

## Backup

`fonts/backup.sh` walks `~/Library/Fonts/`, skips anything already owned by
an installed font cask (derived from `apps/Brewfile`), and copies the rest
into `fonts/user/`. Runs as part of `./backup.sh`.

```bash
./fonts/backup.sh
```

## Install / Restore

`fonts/install.sh` rsyncs `fonts/user/` into `~/Library/Fonts/` with
`--ignore-existing`, so cask-installed files are never overwritten. Runs as
part of `./install.sh`.

```bash
./fonts/install.sh
```

## Adding a Font

- **Has a cask?** Add `cask "font-<name>"` to `apps/Brewfile` and run
  `brew bundle --file=apps/Brewfile`. On the next `./fonts/backup.sh`, the
  script will stop copying that font family into `fonts/user/`.
- **No cask?** Drop the TTF/OTF into `~/Library/Fonts/` as usual. The next
  `./fonts/backup.sh` picks it up and commits it under `fonts/user/`.

## Public Mirror

`fonts/user/` is private-only. The public mirror is scripts-only by contract
(see `.opensource/public-action-filenames.txt`), so binary font files never
leak through the export.

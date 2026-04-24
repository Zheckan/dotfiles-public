# Fonts

Fonts are installed via Homebrew cask entries in the Brewfile (`apps/Brewfile`).

## Install

There is no separate font installer. Fonts are installed when you run:

```bash
../apps/install.sh    # or the root ./install.sh
```

## Adding Fonts

1. Find the Homebrew cask name (e.g., `font-geist-mono`, `font-jetbrains-mono`).
2. Add it to `apps/Brewfile`.
3. Run `brew bundle --file=apps/Brewfile`.

The `fonts/install.sh` script is a no-op that logs this information.

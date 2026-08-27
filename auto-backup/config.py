#!/usr/bin/env python3
"""Validate auto-backup TOML and emit the shell adapter's flat settings."""

from __future__ import annotations

import re
import sys
import tomllib
from pathlib import Path
from typing import NoReturn


REVIEWERS = (
    "claude",
    "codex",
    "agy",
    "opencode",
    "opencode-go-api",
    "cursor",
    "ollama",
)
MODEL_KEYS = {
    "claude": "DOTFILES_REVIEW_CLAUDE_MODELS",
    "codex": "DOTFILES_REVIEW_CODEX_MODELS",
    "agy": "DOTFILES_REVIEW_AGY_MODELS",
    "opencode": "DOTFILES_REVIEW_OPENCODE_MODELS",
    "opencode-go-api": "DOTFILES_REVIEW_OPENCODE_GO_API_MODELS",
    "cursor": "DOTFILES_REVIEW_CURSOR_MODELS",
    "ollama": "DOTFILES_REVIEW_OLLAMA_MODELS",
}
MODEL_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]*$")


def fail(message: str) -> NoReturn:
    print(f"config.py: {message}", file=sys.stderr)
    raise SystemExit(2)


def require_table(container: dict, key: str, location: str) -> dict:
    value = container.get(key)
    if not isinstance(value, dict):
        fail(f"{location}.{key} must be a table")
    return value


def reject_unknown_keys(table: dict, allowed: set[str], location: str) -> None:
    unknown = sorted(set(table) - allowed)
    if unknown:
        fail(f"unsupported key {location}.{unknown[0]}")


def require_bool(table: dict, key: str, location: str) -> bool:
    value = table.get(key)
    if not isinstance(value, bool):
        fail(f"{location}.{key} must be true or false")
    return value


def require_string(table: dict, key: str, location: str) -> str:
    value = table.get(key)
    if not isinstance(value, str) or not value:
        fail(f"{location}.{key} must be a non-empty string")
    return value


def require_string_list(value: object, location: str, *, allow_empty: bool) -> list[str]:
    if not isinstance(value, list) or (not allow_empty and not value):
        qualifier = "a list" if allow_empty else "a non-empty list"
        fail(f"{location} must be {qualifier}")
    if any(not isinstance(item, str) or not item for item in value):
        fail(f"{location} must contain non-empty strings")
    if len(set(value)) != len(value):
        fail(f"{location} must not contain duplicates")
    return value


def load_config(path: Path) -> dict[str, str]:
    try:
        with path.open("rb") as config_file:
            data = tomllib.load(config_file)
    except FileNotFoundError:
        fail(f"configuration file not found: {path}")
    except (OSError, tomllib.TOMLDecodeError) as error:
        fail(f"cannot read {path}: {error}")

    reject_unknown_keys(data, {"backup", "review"}, "root")
    backup = require_table(data, "backup", "root")
    review = require_table(data, "review", "root")
    reject_unknown_keys(backup, {"mode", "rebase"}, "backup")
    reject_unknown_keys(review, {"enabled", "reviewers", "models"}, "review")

    mode = require_string(backup, "mode", "backup")
    if mode not in {"device-only", "main-pc", "pr-only", "test"}:
        fail("backup.mode must be device-only, main-pc, pr-only, or test")
    rebase = require_bool(backup, "rebase", "backup")
    enabled = require_bool(review, "enabled", "review")
    reviewers = require_string_list(
        review.get("reviewers"), "review.reviewers", allow_empty=not enabled
    )
    for reviewer in reviewers:
        if reviewer not in REVIEWERS:
            fail(f"review.reviewers contains unsupported reviewer {reviewer!r}")

    models = require_table(review, "models", "review")
    reject_unknown_keys(models, set(REVIEWERS), "review.models")
    parsed_models: dict[str, list[str]] = {}
    for reviewer, configured_models in models.items():
        parsed = require_string_list(
            configured_models, f"review.models.{reviewer}", allow_empty=False
        )
        for model in parsed:
            if not MODEL_ID.fullmatch(model):
                fail(f"review.models.{reviewer} contains invalid model ID {model!r}")
                if reviewer == "opencode-go-api" and not model.startswith("opencode-go/"):
                    fail(
                        "review.models.opencode-go-api model IDs must start with "
                        "'opencode-go/'"
                    )
        parsed_models[reviewer] = parsed

    if enabled:
        for reviewer in reviewers:
            if reviewer not in parsed_models:
                fail(f"review.models.{reviewer} is required when review is enabled")

    flattened = {
        "DOTFILES_AUTOBACKUP_MODE": mode,
        "DOTFILES_AUTOBACKUP_REBASE": str(rebase).lower(),
        "DOTFILES_AUTOBACKUP_REVIEW": str(enabled).lower(),
        "DOTFILES_REVIEWERS": ",".join(reviewers),
    }
    for reviewer, variable in MODEL_KEYS.items():
        flattened[variable] = ",".join(parsed_models.get(reviewer, []))
    return flattened


def main() -> None:
    if len(sys.argv) != 2:
        fail("usage: config.py CONFIG_FILE")
    for key, value in load_config(Path(sys.argv[1])).items():
        print(f"{key}\t{value}")


if __name__ == "__main__":
    main()

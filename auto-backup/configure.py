#!/usr/bin/env python3
"""Full-screen setup wizard for unattended dotfiles backups."""

from __future__ import annotations

import argparse
import curses
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import textwrap
import time
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

import opencode_go


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_DIR = SCRIPT_DIR.parent
CONFIG_FILE = SCRIPT_DIR / "config.local.toml"
ENV_FILE = SCRIPT_DIR / ".env"
MODEL_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]*$")


class Cancelled(Exception):
    """The user cancelled without saving."""


class GoModelsBack(Exception):
    """The user returned from Go credential setup to model selection."""


@dataclass(frozen=True)
class Choice:
    value: str
    label: str
    description: str
    experimental: bool = False


@dataclass
class SetupState:
    mode: str = "device-only"
    rebase: bool = True
    review: bool = False
    reviewers: list[str] = field(default_factory=list)
    models: dict[str, list[str]] = field(default_factory=dict)
    pending_go_key: str | None = None
    go_key_source: str = ""


MODES = [
    Choice(
        "main-pc",
        "Full automatic PR and merge (main-pc)",
        "Back up this machine, create or update a PR, run AI review, and "
        "squash-merge only when the review approves it.",
    ),
    Choice(
        "device-only",
        "Device branch backup only (device-only)",
        "Back up and push this machine's device branch. Do not create, review, "
        "or merge a pull request.",
    ),
    Choice(
        "pr-only",
        "Create and review a PR (pr-only)",
        "Back up this machine, create or update a PR, and run AI review. Leave "
        "the PR open even when approved.",
    ),
    Choice(
        "test",
        "Test the current branch (test)",
        "Push and review the current development branch without running backup "
        "or merging. Intended for validating the review pipeline.",
    ),
]

REVIEWERS = [
    Choice(
        "claude",
        "Claude Code",
        "Uses the authenticated Claude Code CLI in non-interactive print mode.",
    ),
    Choice(
        "codex",
        "Codex",
        "Uses Codex exec with a read-only sandbox.",
    ),
    Choice(
        "agy",
        "Google Antigravity (AGY)",
        "Uses AGY's plan mode, sandbox, and streaming JSON interface.",
    ),
    Choice(
        "opencode",
        "OpenCode CLI",
        "Uses your existing OpenCode provider login and its read-only plan agent.",
    ),
    Choice(
        "opencode-go-api",
        "OpenCode Go direct API",
        "Separate from the CLI. Uses a Zen API key and sends PR diffs directly "
        "to documented Go endpoints for your own internal reviews.",
    ),
    Choice(
        "cursor",
        "Cursor",
        "Selector exists but unattended review support still fails closed.",
        experimental=True,
    ),
    Choice(
        "ollama",
        "Ollama",
        "Selector exists but unattended review support still fails closed.",
        experimental=True,
    ),
]

BOOLEAN_CHOICES = [
    Choice("true", "Yes", ""),
    Choice("false", "No", ""),
]


def toggle_selection(selected: list[str], value: str) -> list[str]:
    result = list(selected)
    if value in result:
        result.remove(value)
    else:
        result.append(value)
    return result


def move_selection(selected: list[str], value: str, direction: int) -> list[str]:
    result = list(selected)
    if value not in result:
        return result
    index = result.index(value)
    target = max(0, min(len(result) - 1, index + direction))
    if target != index:
        result[index], result[target] = result[target], result[index]
    return result


def explain_go_error(error: BaseException) -> str:
    message = opencode_go.safe_error(error)
    lowered = message.lower()
    if "request blocked by upstream provider" in lowered:
        return (
            "The key was recognized, but OpenCode blocked this account or workspace "
            "before contacting the model provider. Rotating the key will not fix an "
            "account entitlement block."
        )
    if "http 401" in lowered:
        return (
            "Authentication was rejected (HTTP 401). Confirm this is the API key "
            "from an active OpenCode Go subscription, not an OAuth credential."
        )
    if "http 403" in lowered:
        return (
            "OpenCode refused the request (HTTP 403). This can be an account, "
            "subscription, region, or edge-access restriction; it does not prove "
            "the key itself is invalid."
        )
    if "http 429" in lowered:
        return "The OpenCode Go account is currently rate- or usage-limited (HTTP 429)."
    if "network error" in lowered:
        return f"OpenCode Go could not be reached: {message}"
    return f"OpenCode Go validation failed: {message}"


def validate_go_key(model: str, api_key: str) -> str:
    return opencode_go.run_inference(
        model,
        "Reply with exactly OK.",
        api_key,
        opencode_go.VALIDATION_MAX_TOKENS,
    )


def run_command(command: list[str], *, timeout: int = 60) -> str:
    completed = subprocess.run(
        command,
        check=True,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    return completed.stdout


def choices_from_lines(output: str) -> list[Choice]:
    choices: list[Choice] = []
    seen: set[str] = set()
    for raw_line in output.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        value, _, label = line.partition("\t")
        if value in seen:
            continue
        seen.add(value)
        choices.append(Choice(value, label or value, value))
    return choices


def discover_models(reviewer: str, api_key: str = "") -> tuple[list[Choice], str]:
    try:
        if reviewer == "claude":
            return (
                [
                    Choice("default", "Configured default", "Use the CLI's current default."),
                    Choice("sonnet", "Sonnet stable alias", "Account-aware stable alias."),
                    Choice(
                        "fable",
                        "Fable stable alias",
                        "Claude Fable for complex and long-running tasks.",
                    ),
                    Choice("opus", "Opus stable alias", "Most capable stable alias."),
                    Choice("haiku", "Haiku stable alias", "Fast stable alias."),
                ],
                "Claude Code has no machine-readable model catalog; stable aliases are shown.",
            )
        if reviewer == "agy":
            output = run_command(["agy", "models"])
            choices = choices_from_lines(output)
        elif reviewer == "opencode":
            output = run_command(["opencode", "models", "--refresh"])
            choices = [
                Choice(line.strip(), line.strip(), line.strip())
                for line in output.splitlines()
                if "/" in line and not line.isspace()
            ]
        elif reviewer == "codex":
            payload = json.loads(run_command(["codex", "debug", "models"]))
            choices = [
                Choice(model["slug"], model.get("display_name") or model["slug"], model["slug"])
                for model in payload.get("models", [])
                if isinstance(model, dict) and isinstance(model.get("slug"), str)
            ]
        elif reviewer == "opencode-go-api":
            choices = [
                Choice(model, model.removeprefix("opencode-go/"), model)
                for model in opencode_go.list_models(api_key)
            ]
            return choices, "Live catalog loaded from the OpenCode Go API."
        else:
            return [Choice("default", "Configured default", "Experimental selector.")], (
                "This reviewer is experimental and fails closed during unattended review."
            )
    except (FileNotFoundError, subprocess.SubprocessError, ValueError, opencode_go.AdapterError) as error:
        return [], f"Model discovery failed: {error}"

    if reviewer != "opencode-go-api":
        choices.insert(0, Choice("default", "Configured default", "Use the CLI's current default."))
    return choices, "Live account-aware model catalog loaded."


def load_state(path: Path = CONFIG_FILE) -> tuple[SetupState, str]:
    if not path.exists():
        return SetupState(), ""
    try:
        with path.open("rb") as config_file:
            data = tomllib.load(config_file)
        backup = data["backup"]
        review = data["review"]
        mode = backup["mode"]
        rebase = backup["rebase"]
        enabled = review["enabled"]
        reviewers = list(review["reviewers"])
        models = {
            reviewer: list(configured)
            for reviewer, configured in review.get("models", {}).items()
        }
        allowed_reviewers = {choice.value for choice in REVIEWERS}
        if mode not in {choice.value for choice in MODES}:
            raise ValueError(f"unsupported backup mode {mode!r}")
        if not isinstance(rebase, bool) or not isinstance(enabled, bool):
            raise ValueError("backup.rebase and review.enabled must be booleans")
        if (
            any(reviewer not in allowed_reviewers for reviewer in reviewers)
            or len(reviewers) != len(set(reviewers))
        ):
            raise ValueError("review.reviewers contains invalid or duplicate values")
        for reviewer in reviewers:
            configured = models.get(reviewer)
            if not configured or any(
                not isinstance(model, str) or not MODEL_ID.fullmatch(model)
                for model in configured
            ):
                raise ValueError(f"review.models.{reviewer} is missing or invalid")
            if reviewer == "opencode-go-api" and any(
                not model.startswith("opencode-go/") for model in configured
            ):
                raise ValueError("OpenCode Go model IDs must start with opencode-go/")
        return (
            SetupState(
                mode=mode,
                rebase=rebase,
                review=enabled,
                reviewers=reviewers,
                models=models,
            ),
            "",
        )
    except (KeyError, OSError, TypeError, ValueError, tomllib.TOMLDecodeError) as error:
        return SetupState(), f"Existing config could not be loaded; using safe defaults: {error}"


def toml_array(values: list[str]) -> str:
    return "[" + ", ".join(json.dumps(value) for value in values) + "]"


def render_config(state: SetupState) -> str:
    lines = [
        "# Generated by auto-backup/configure.sh.",
        "# Shortcuts and LaunchAgent should call run-backup.sh without mode flags.",
        "",
        "[backup]",
        f'mode = "{state.mode}"',
        f"rebase = {str(state.rebase).lower()}",
        "",
        "[review]",
        f"enabled = {str(state.review).lower()}",
        f"reviewers = {toml_array(state.reviewers)}",
        "",
        "[review.models]",
    ]
    for reviewer in state.reviewers:
        lines.append(f"{reviewer} = {toml_array(state.models[reviewer])}")
    return "\n".join(lines) + "\n"


def atomic_write(path: Path, content: str, mode: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temp_path = Path(temp_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as temp_file:
            temp_file.write(content)
            temp_file.flush()
            os.fsync(temp_file.fileno())
        temp_path.chmod(mode)
        temp_path.replace(path)
    except BaseException:
        temp_path.unlink(missing_ok=True)
        raise


def ensure_secret_not_tracked() -> None:
    completed = subprocess.run(
        ["git", "-C", str(REPO_DIR), "ls-files", "--error-unmatch", "auto-backup/.env"],
        capture_output=True,
        check=False,
    )
    if completed.returncode == 0:
        raise RuntimeError("refusing to write tracked auto-backup/.env")


def save_state(state: SetupState) -> Path | None:
    backup_path: Path | None = None
    if state.pending_go_key is not None:
        ensure_secret_not_tracked()
    if CONFIG_FILE.exists():
        backup_path = Path(
            tempfile.gettempdir(),
            f"dotfiles-config.toml.backup.{time.strftime('%Y%m%d-%H%M%S')}",
        )
        shutil.copy2(CONFIG_FILE, backup_path)
    atomic_write(CONFIG_FILE, render_config(state), 0o600)
    if state.pending_go_key is not None:
        atomic_write(ENV_FILE, f"OPENCODE_GO_API_KEY={state.pending_go_key}\n", 0o600)
    return backup_path


class Wizard:
    def __init__(self, screen: curses.window, state: SetupState, warning: str = "") -> None:
        self.screen = screen
        self.state = state
        self.warning = warning
        self._init_screen()

    def _init_screen(self) -> None:
        curses.curs_set(0)
        self.screen.keypad(True)
        if curses.has_colors():
            curses.start_color()
            try:
                curses.use_default_colors()
                background = -1
            except curses.error:
                background = curses.COLOR_BLACK
            curses.init_pair(1, curses.COLOR_CYAN, background)
            curses.init_pair(2, curses.COLOR_GREEN, background)
            curses.init_pair(3, curses.COLOR_YELLOW, background)
            curses.init_pair(4, curses.COLOR_RED, background)

    def add(self, y: int, x: int, text: str, style: int = 0) -> None:
        height, width = self.screen.getmaxyx()
        if 0 <= y < height and x < width:
            try:
                self.screen.addnstr(y, x, text, max(0, width - x - 1), style)
            except curses.error:
                pass

    def wrapped(self, y: int, text: str, style: int = 0, indent: int = 0) -> int:
        _, width = self.screen.getmaxyx()
        for line in textwrap.wrap(text, max(20, width - indent - 2)) or [""]:
            self.add(y, indent, line, style)
            y += 1
        return y

    def frame(self, title: str, subtitle: str = "") -> int:
        self.screen.erase()
        height, width = self.screen.getmaxyx()
        if height < 18 or width < 68:
            self.add(0, 0, "Terminal is too small. Resize to at least 68x18.", curses.A_BOLD)
            self.screen.refresh()
            return 3
        self.add(0, 2, "Auto-backup setup", curses.A_BOLD | curses.color_pair(1))
        self.add(2, 2, title, curses.A_BOLD)
        y = 3
        if subtitle:
            y = self.wrapped(y, subtitle, curses.A_DIM, 2)
        return y + 1

    def footer(self, text: str) -> None:
        height, width = self.screen.getmaxyx()
        lines = textwrap.wrap(text, max(20, width - 4))[-2:]
        start = height - len(lines)
        for offset, line in enumerate(lines):
            self.add(start + offset, 2, line, curses.A_DIM)

    def cancel(self) -> None:
        choice = self.select_one(
            "Cancel setup?",
            [
                Choice("no", "Return to setup", "Keep editing without saving yet."),
                Choice("yes", "Cancel without saving", "Leave existing files unchanged."),
            ],
            "no",
            allow_back=False,
            allow_cancel=False,
        )
        if choice == "yes":
            raise Cancelled

    def select_one(
        self,
        title: str,
        choices: list[Choice],
        initial: str,
        *,
        subtitle: str = "",
        allow_back: bool = True,
        allow_cancel: bool = True,
    ) -> str:
        index = next((i for i, choice in enumerate(choices) if choice.value == initial), 0)
        while True:
            y = self.frame(title, subtitle)
            for item_index, choice in enumerate(choices):
                marker = "●" if item_index == index else "○"
                style = curses.A_BOLD if item_index == index else 0
                if item_index == index:
                    style |= curses.color_pair(1)
                self.add(y + item_index, 4, f"{marker} {choice.label}", style)
            detail_y = y + len(choices) + 1
            self.add(detail_y, 2, "What this does", curses.A_BOLD | curses.color_pair(1))
            self.wrapped(detail_y + 1, choices[index].description, 0, 4)
            self.footer("↑↓ choose  •  Enter confirm  •  Esc back  •  Q cancel")
            self.screen.refresh()
            key = self.screen.getch()
            if key in (curses.KEY_UP, ord("k")):
                index = (index - 1) % len(choices)
            elif key in (curses.KEY_DOWN, ord("j")):
                index = (index + 1) % len(choices)
            elif key in (10, 13, curses.KEY_ENTER):
                return choices[index].value
            elif key == 27 and allow_back:
                return "__back__"
            elif key in (ord("q"), ord("Q")):
                if allow_cancel:
                    self.cancel()
                else:
                    raise Cancelled

    def select_ordered(
        self,
        title: str,
        choices: list[Choice],
        selected: list[str],
        *,
        subtitle: str,
        allow_manual: bool = False,
        manual_prefix: str = "",
    ) -> list[str] | None:
        known = {choice.value for choice in choices}
        for value in selected:
            if value not in known:
                choices.append(Choice(value, value, "Previously configured or manually entered."))
                known.add(value)
        index = 0
        offset = 0
        message = ""
        while True:
            height, _ = self.screen.getmaxyx()
            y = self.frame(title, subtitle)
            list_height = max(4, height - y - 10)
            if index < offset:
                offset = index
            if index >= offset + list_height:
                offset = index - list_height + 1
            visible = choices[offset : offset + list_height]
            for row, choice in enumerate(visible):
                item_index = offset + row
                order = selected.index(choice.value) + 1 if choice.value in selected else 0
                marker = f"[{order}]" if order else "[ ]"
                style = curses.color_pair(2) if order else 0
                if choice.experimental:
                    style = curses.color_pair(3)
                if item_index == index:
                    style |= curses.A_REVERSE | curses.A_BOLD
                self.add(y + row, 4, f"{marker:<4} {choice.label}", style)
            detail_y = y + list_height + 1
            selected_labels = [
                next((choice.label for choice in choices if choice.value == value), value)
                for value in selected
            ]
            order_text = " → ".join(
                f"{position}. {label}" for position, label in enumerate(selected_labels, 1)
            ) or "Nothing selected"
            self.add(detail_y, 2, "Selected order", curses.A_BOLD | curses.color_pair(1))
            next_y = self.wrapped(detail_y + 1, order_text, curses.color_pair(2), 4)
            if choices:
                self.wrapped(next_y, choices[index].description, curses.A_DIM, 4)
            if message:
                self.add(height - 3, 2, message, curses.color_pair(4))
            manual_help = "  •  M manual ID" if allow_manual else ""
            self.footer(
                f"↑↓ navigate  •  Space select/remove  •  ←→ reorder{manual_help}"
                "  •  Enter confirm  •  Esc back  •  Q cancel"
            )
            self.screen.refresh()
            key = self.screen.getch()
            message = ""
            if key in (curses.KEY_UP, ord("k")) and choices:
                index = (index - 1) % len(choices)
            elif key in (curses.KEY_DOWN, ord("j")) and choices:
                index = (index + 1) % len(choices)
            elif key == ord(" ") and choices:
                selected = toggle_selection(selected, choices[index].value)
            elif key == curses.KEY_LEFT and choices:
                selected = move_selection(selected, choices[index].value, -1)
            elif key == curses.KEY_RIGHT and choices:
                selected = move_selection(selected, choices[index].value, 1)
            elif key in (ord("m"), ord("M")) and allow_manual:
                manual = self.prompt_text("Manual model ID", secret=False)
                if manual and not MODEL_ID.fullmatch(manual):
                    message = (
                        "Model IDs may contain letters, numbers, dots, underscores, "
                        "slashes, and hyphens."
                    )
                elif manual and manual_prefix and not manual.startswith(manual_prefix):
                    message = f"This model ID must start with {manual_prefix}."
                elif manual and manual not in known:
                    choices.append(Choice(manual, manual, "Manually entered model ID."))
                    known.add(manual)
                    selected.append(manual)
                    index = len(choices) - 1
            elif key in (10, 13, curses.KEY_ENTER):
                if selected:
                    return selected
                message = "Select at least one item before continuing."
            elif key == 27:
                return None
            elif key in (ord("q"), ord("Q")):
                self.cancel()

    def prompt_text(self, title: str, *, secret: bool) -> str | None:
        value: list[str] = []
        curses.curs_set(1)
        try:
            while True:
                y = self.frame(
                    title,
                    "Paste the OpenCode Zen API key. It is never displayed or passed "
                    "as a command-line argument." if secret else "Enter a model identifier.",
                )
                shown = "•" * len(value) if secret else "".join(value)
                self.add(y, 4, "> " + shown, curses.color_pair(1))
                self.footer("Enter confirm  •  Esc back  •  Backspace delete")
                self.screen.move(y, min(self.screen.getmaxyx()[1] - 2, 6 + len(shown)))
                self.screen.refresh()
                key = self.screen.getch()
                if key in (10, 13, curses.KEY_ENTER):
                    result = "".join(value).strip()
                    if result:
                        return result
                elif key == 27:
                    return None
                elif key in (curses.KEY_BACKSPACE, 127, 8):
                    if value:
                        value.pop()
                elif 32 <= key <= 126:
                    value.append(chr(key))
        finally:
            curses.curs_set(0)

    def status(self, title: str, message: str) -> None:
        y = self.frame(title)
        self.wrapped(y, message, curses.A_BOLD | curses.color_pair(1), 4)
        self.screen.refresh()

    def go_credential(self) -> str:
        env_key = os.environ.get(opencode_go.ENV_KEY, "")
        key = env_key
        source = "inherited environment" if key else ""
        if not key and ENV_FILE.exists():
            try:
                key = opencode_go.read_env_key(ENV_FILE)
                source = "auto-backup/.env"
            except opencode_go.AdapterError as error:
                problem = explain_go_error(error)
                key = ""
                source = ""
            else:
                problem = ""
        else:
            problem = ""

        while True:
            if key:
                model = self.state.models["opencode-go-api"][0]
                self.status("Validating OpenCode Go", f"Testing {model} using {source}…")
                try:
                    validate_go_key(model, key)
                except opencode_go.AdapterError as error:
                    problem = explain_go_error(error)
                else:
                    self.state.go_key_source = source
                    if source == "new key":
                        self.state.pending_go_key = key
                    return "ok"

            action = self.select_one(
                "OpenCode Go credential",
                [
                    Choice("retry", "Enter a different API key", "Validate another Zen Go key."),
                    Choice(
                        "remove",
                        "Remove OpenCode Go and continue",
                        "Keep the rest of the reviewer order and do not configure this API.",
                    ),
                    Choice(
                        "models",
                        "Back to Go model selection",
                        "Choose a different primary model before validating again.",
                    ),
                    Choice("cancel", "Cancel setup", "Leave existing configuration unchanged."),
                ],
                "retry",
                subtitle=problem or "No OpenCode Go API key is configured.",
                allow_back=False,
            )
            if action == "retry":
                entered = self.prompt_text("OpenCode Go API key", secret=True)
                if entered is None:
                    continue
                key = entered
                source = "new key"
                problem = ""
            elif action == "remove":
                return "remove"
            elif action == "models":
                raise GoModelsBack
            elif action == "cancel":
                raise Cancelled

    def summary(self) -> bool:
        reviewer_labels = {
            choice.value: choice.label for choice in REVIEWERS
        }
        lines = [
            f"Mode: {next(choice.label for choice in MODES if choice.value == self.state.mode)}",
            f"Rebase before backup: {'yes' if self.state.rebase else 'no'}",
            f"AI review: {'enabled' if self.state.review else 'disabled'}",
        ]
        if self.state.review:
            lines.append(
                "Review order: "
                + " → ".join(
                    reviewer_labels.get(reviewer, reviewer)
                    for reviewer in self.state.reviewers
                )
            )
            for reviewer in self.state.reviewers:
                lines.append(f"{reviewer}: {' → '.join(self.state.models[reviewer])}")
        choice = self.select_one(
            "Review and save",
            [
                Choice("save", "Save configuration", "Atomically write config.local.toml."),
                Choice("back", "Back to setup", "Return to the first screen and adjust choices."),
                Choice("cancel", "Cancel without saving", "Leave existing files unchanged."),
            ],
            "save",
            subtitle="\n".join(lines),
            allow_back=False,
        )
        if choice == "cancel":
            raise Cancelled
        return choice == "save"

    def run(self) -> None:
        if self.warning:
            self.select_one(
                "Existing configuration warning",
                [Choice("continue", "Continue with safe defaults", self.warning)],
                "continue",
                allow_back=False,
            )
        stage = "mode"
        model_index = 0
        summary_back = "review"
        while True:
            if stage == "mode":
                mode = self.select_one(
                    "Choose auto-backup behavior",
                    MODES,
                    self.state.mode,
                    subtitle="The config ID is shown in parentheses after selection.",
                )
                if mode == "__back__":
                    self.cancel()
                else:
                    self.state.mode = mode
                    stage = "rebase"

            elif stage == "rebase":
                rebase = self.select_one(
                    "Rebase on main before backup?",
                    [
                        Choice(
                            "true",
                            "Yes — start from current main",
                            "Fetch and rebase the device branch before capturing new changes.",
                        ),
                        Choice(
                            "false",
                            "No — keep the current branch base",
                            "Skip the rebase step for this machine.",
                        ),
                    ],
                    str(self.state.rebase).lower(),
                )
                if rebase == "__back__":
                    stage = "mode"
                else:
                    self.state.rebase = rebase == "true"
                    stage = "review"

            elif stage == "review":
                review = self.select_one(
                    "Run AI review for PR modes?",
                    [
                        Choice(
                            "true",
                            "Yes — require an AI verdict",
                            "Try the selected reviewers and model fallbacks in order.",
                        ),
                        Choice(
                            "false",
                            "No — do not run AI review",
                            "PR modes will not receive an automated review verdict.",
                        ),
                    ],
                    str(self.state.review).lower(),
                )
                if review == "__back__":
                    stage = "rebase"
                    continue
                self.state.review = review == "true"
                if self.state.review:
                    stage = "reviewers"
                else:
                    self.state.reviewers = []
                    self.state.models = {}
                    summary_back = "review"
                    stage = "summary"

            elif stage == "reviewers":
                selected = self.select_ordered(
                    "Select and order reviewers",
                    list(REVIEWERS),
                    self.state.reviewers,
                    subtitle=(
                        "Numbers are fallback priority. Space selects or removes; "
                        "Left/Right changes the highlighted reviewer's priority."
                    ),
                )
                if selected is None:
                    stage = "review"
                    continue
                self.state.reviewers = selected
                self.state.models = {
                    reviewer: models
                    for reviewer, models in self.state.models.items()
                    if reviewer in selected
                }
                model_index = 0
                stage = "models"

            elif stage == "models":
                if model_index >= len(self.state.reviewers):
                    if "opencode-go-api" in self.state.reviewers:
                        stage = "credential"
                    else:
                        summary_back = "reviewers"
                        stage = "summary"
                    continue

                reviewer = self.state.reviewers[model_index]
                current_key = os.environ.get(opencode_go.ENV_KEY, "")
                if not current_key and ENV_FILE.exists():
                    try:
                        current_key = opencode_go.read_env_key(ENV_FILE)
                    except opencode_go.AdapterError:
                        current_key = ""
                self.status("Loading models", f"Discovering models for {reviewer}…")
                choices, discovery_note = discover_models(reviewer, current_key)
                existing = self.state.models.get(reviewer, [])
                if not choices and existing:
                    choices = [
                        Choice(model, model, "Previously configured model.")
                        for model in existing
                    ]
                models = self.select_ordered(
                    f"Models for {reviewer}",
                    choices,
                    existing,
                    subtitle=discovery_note,
                    allow_manual=True,
                    manual_prefix=(
                        "opencode-go/" if reviewer == "opencode-go-api" else ""
                    ),
                )
                if models is None:
                    if model_index == 0:
                        stage = "reviewers"
                    else:
                        model_index -= 1
                    continue
                self.state.models[reviewer] = models
                model_index += 1

            elif stage == "credential":
                try:
                    action = self.go_credential()
                except GoModelsBack:
                    model_index = self.state.reviewers.index("opencode-go-api")
                    stage = "models"
                    continue
                if action == "remove":
                    self.state.reviewers.remove("opencode-go-api")
                    self.state.models.pop("opencode-go-api", None)
                summary_back = "reviewers"
                stage = "summary"

            elif stage == "summary":
                if self.summary():
                    return
                stage = summary_back


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Configure unattended dotfiles backup and AI review."
    )
    return parser.parse_args()


def main() -> int:
    parse_args()
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        print("configure.py requires an interactive terminal.", file=sys.stderr)
        return 1
    state, warning = load_state()
    try:
        curses.wrapper(lambda screen: Wizard(screen, state, warning).run())
    except Cancelled:
        print("Setup cancelled; existing configuration was not changed.")
        return 130
    try:
        backup = save_state(state)
    except (OSError, RuntimeError) as error:
        print(f"configure.py: could not save configuration: {error}", file=sys.stderr)
        return 2
    print(f"Saved {CONFIG_FILE}")
    if backup:
        print(f"Previous config backed up to {backup}")
    if state.pending_go_key is not None:
        print(f"Saved {ENV_FILE} with mode 0600")
    print(f'Run: export DOTFILES_REPO_DIR="{REPO_DIR}"')
    print('"$DOTFILES_REPO_DIR/auto-backup/run-backup.sh"')
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

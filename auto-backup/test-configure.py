#!/usr/bin/env python3
"""Offline tests for the Python setup wizard."""

from __future__ import annotations

import stat
import sys
import tempfile
import unittest
from io import StringIO
from pathlib import Path
from unittest import mock


sys.path.insert(0, str(Path(__file__).resolve().parent))
import configure  # noqa: E402


class ConfigureWizardTests(unittest.TestCase):
    def test_model_selection_changes_reasoning_in_place(self) -> None:
        class Screen:
            def __init__(self) -> None:
                self.keys = [ord("r"), 10]
                self.lines: list[str] = []

            def getmaxyx(self) -> tuple[int, int]:
                return 30, 100

            def erase(self) -> None:
                pass

            def addnstr(
                self, _y: int, _x: int, text: str, _length: int, _style: int
            ) -> None:
                self.lines.append(text)

            def refresh(self) -> None:
                pass

            def getch(self) -> int:
                return self.keys.pop(0)

        screen = Screen()
        wizard = object.__new__(configure.Wizard)
        wizard.screen = screen
        reasoning = {"haiku": "default"}

        with mock.patch.object(configure.curses, "color_pair", return_value=0):
            selected = wizard.select_ordered(
                "Models for claude",
                [
                    configure.Choice(
                        "haiku",
                        "Haiku",
                        "Claude Haiku",
                        reasoning_levels=("off", "on"),
                    )
                ],
                ["haiku"],
                subtitle="",
                reasoning=reasoning,
            )

        self.assertEqual(selected, ["haiku"])
        self.assertEqual(reasoning, {"haiku": "off"})
        self.assertTrue(any("Haiku [off]" in line for line in screen.lines))

    def test_wizard_finishes_without_a_separate_reasoning_screen(self) -> None:
        wizard = object.__new__(configure.Wizard)
        wizard.state = configure.SetupState()
        wizard.warning = ""
        wizard.existing_config = False

        def select_one(title: str, *_args: object, **_kwargs: object) -> str:
            answers = {
                "Choose auto-backup behavior": "pr-only",
                "Rebase on main before backup?": "true",
                "Run AI review for PR modes?": "true",
                "Review and save": "save",
            }
            if title not in answers:
                raise AssertionError(f"unexpected separate screen: {title}")
            return answers[title]

        def select_ordered(
            title: str, *_args: object, **kwargs: object
        ) -> list[str]:
            if title == "Select and order reviewers":
                return ["claude"]
            if title == "Models for claude":
                reasoning = kwargs.get("reasoning")
                self.assertIsInstance(reasoning, dict)
                reasoning["opus"] = "high"
                return ["opus"]
            raise AssertionError(title)

        wizard.select_one = select_one
        wizard.select_ordered = select_ordered
        wizard.status = lambda *_args, **_kwargs: None

        wizard.run()

        self.assertEqual(wizard.state.models, {"claude": ["opus"]})
        self.assertEqual(wizard.state.reasoning, {"claude": {"opus": "high"}})

    def test_modes_explain_their_end_to_end_behavior(self) -> None:
        descriptions = {choice.value: choice.description for choice in configure.MODES}
        self.assertIn("squash-merge", descriptions["main-pc"])
        self.assertIn("Do not create", descriptions["device-only"])
        self.assertIn("Leave the PR open", descriptions["pr-only"])
        self.assertIn("without running backup", descriptions["test"])

    def test_claude_discovery_orders_stable_aliases_before_default(self) -> None:
        choices, _ = configure.discover_models("claude")
        self.assertEqual(
            [choice.value for choice in choices],
            ["fable", "opus", "sonnet", "haiku", "default"],
        )

    def test_claude_discovery_uses_model_specific_reasoning_controls(self) -> None:
        choices, _ = configure.discover_models("claude")
        levels = {choice.value: choice.reasoning_levels for choice in choices}

        self.assertEqual(levels["haiku"], ("off", "on"))
        self.assertEqual(
            levels["opus"], ("low", "medium", "high", "xhigh", "max")
        )
        self.assertEqual(levels["default"], ())

    def test_codex_discovery_reads_reasoning_levels_from_model_catalog(self) -> None:
        catalog = {
            "models": [
                {
                    "slug": "gpt-5.6-luna",
                    "display_name": "GPT-5.6 Luna",
                    "supported_reasoning_levels": [
                        {"effort": "low", "description": "Fast"},
                        {"effort": "medium", "description": "Balanced"},
                    ],
                }
            ]
        }
        with mock.patch.object(
            configure, "run_command", return_value=configure.json.dumps(catalog)
        ):
            choices, _ = configure.discover_models("codex")

        luna = next(choice for choice in choices if choice.value == "gpt-5.6-luna")
        self.assertEqual(luna.reasoning_levels, ("low", "medium"))

    def test_opencode_discovery_reads_each_models_variant_names(self) -> None:
        output = """\
opencode-go/grok-4.6
{"name":"Grok 4.6","variants":{"low":{},"high":{},"xhigh":{}}}
opencode-go/kimi-k3
{"name":"Kimi K3","variants":{"max":{}}}
"""
        with mock.patch.object(configure, "run_command", return_value=output):
            choices, _ = configure.discover_models("opencode")

        levels = {choice.value: choice.reasoning_levels for choice in choices}
        self.assertEqual(
            levels["opencode-go/grok-4.6"], ("low", "high", "xhigh")
        )
        self.assertEqual(levels["opencode-go/kimi-k3"], ("max",))

    def test_opencode_discovery_keeps_provider_in_visible_labels(self) -> None:
        output = """\
opencode-go/gpt-5.6-sol
{"name":"GPT-5.6 Sol","variants":{"high":{}}}
openai/gpt-5.4
{"name":"GPT-5.4","variants":{"high":{}}}
"""
        with mock.patch.object(configure, "run_command", return_value=output):
            choices, _ = configure.discover_models("opencode")

        labels = {choice.value: choice.label for choice in choices}
        self.assertEqual(
            labels["opencode-go/gpt-5.6-sol"],
            "opencode-go/gpt-5.6-sol",
        )
        self.assertEqual(
            labels["openai/gpt-5.4"],
            "openai/gpt-5.4",
        )

    def test_selection_and_order_are_one_state(self) -> None:
        selected: list[str] = []
        selected = configure.toggle_selection(selected, "claude")
        selected = configure.toggle_selection(selected, "agy")
        selected = configure.toggle_selection(selected, "opencode")
        self.assertEqual(selected, ["claude", "agy", "opencode"])

        selected = configure.move_selection(selected, "opencode", -1)
        self.assertEqual(selected, ["claude", "opencode", "agy"])
        selected = configure.toggle_selection(selected, "opencode")
        self.assertEqual(selected, ["claude", "agy"])

    def test_config_render_round_trips(self) -> None:
        state = configure.SetupState(
            mode="pr-only",
            rebase=False,
            review=True,
            reviewers=["agy", "codex", "opencode-go-api"],
            models={
                "agy": ["gemini-3.7-flash-low"],
                "codex": ["gpt-5.6-sol"],
                "opencode-go-api": ["opencode-go/deepseek-v4-flash"],
            },
            reasoning={
                "codex": {"gpt-5.6-sol": "high"},
                "opencode-go-api": {
                    "opencode-go/deepseek-v4-flash": "default"
                },
            },
        )
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir, "config.local.toml")
            configure.atomic_write(path, configure.render_config(state), 0o600)
            loaded, warning = configure.load_state(path)

            self.assertEqual(warning, "")
            self.assertEqual(loaded, state)
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)

    def test_legacy_config_defaults_cli_reasoning_without_changing_agy_models(self) -> None:
        legacy = """\
[backup]
mode = "pr-only"
rebase = true

[review]
enabled = true
reviewers = ["agy", "claude", "codex", "opencode", "opencode-go-api"]

[review.models]
agy = ["gemini-3.8-flash-high"]
claude = ["opus"]
codex = ["gpt-5.6-sol"]
opencode = ["opencode-go/grok-4.6"]
opencode-go-api = ["opencode-go/deepseek-v4-flash"]
"""
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir, "config.local.toml")
            configure.atomic_write(path, legacy, 0o600)
            loaded, warning = configure.load_state(path)

        self.assertEqual(warning, "")
        self.assertEqual(
            loaded.reasoning,
            {
                "claude": {"opus": "default"},
                "codex": {"gpt-5.6-sol": "default"},
                "opencode": {"opencode-go/grok-4.6": "default"},
                "opencode-go-api": {
                    "opencode-go/deepseek-v4-flash": "default"
                },
            },
        )
        self.assertNotIn("agy", loaded.reasoning)

    def test_legacy_generic_claude_effort_is_normalized_for_haiku(self) -> None:
        legacy = """\
[backup]
mode = "pr-only"
rebase = true

[review]
enabled = true
reviewers = ["claude"]

[review.models]
claude = ["haiku"]

[review.reasoning.claude]
haiku = "high"
"""
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir, "config.local.toml")
            configure.atomic_write(path, legacy, 0o600)
            loaded, warning = configure.load_state(path)

        self.assertEqual(warning, "")
        self.assertEqual(loaded.reasoning, {"claude": {"haiku": "default"}})

    def test_reasoning_choices_only_include_the_selected_models_controls(self) -> None:
        self.assertEqual(
            [
                choice.value
                for choice in configure.reasoning_choices(("low", "high"))
            ],
            ["default", "low", "high"],
        )
        self.assertEqual(configure.reasoning_choices(()), [])

    def test_go_403_is_not_reported_as_an_invalid_key(self) -> None:
        message = configure.explain_go_error(
            configure.opencode_go.AdapterError("HTTP 403")
        )
        self.assertIn("does not prove", message)
        self.assertNotIn("invalid key", message.lower())

    def test_go_validation_uses_provider_minimum_output_tokens(self) -> None:
        with mock.patch.object(
            configure.opencode_go, "run_inference", return_value="OK"
        ) as run:
            configure.validate_go_key(
                "opencode-go/gpt-5.6-luna", "secret-key"
            )
        self.assertEqual(
            run.call_args.args[-1],
            configure.opencode_go.VALIDATION_MAX_TOKENS,
        )
        self.assertGreaterEqual(run.call_args.args[-1], 16)

    def test_go_models_use_live_api_catalog(self) -> None:
        with mock.patch.object(
            configure.opencode_go,
            "list_models",
            return_value=["opencode-go/deepseek-v4-flash"],
        ) as list_models, mock.patch.object(
            configure,
            "run_command",
            return_value=(
                'opencode-go/deepseek-v4-flash\n'
                '{"name":"DeepSeek V4 Flash",'
                '"variants":{"low":{},"high":{},"max":{}}}\n'
            ),
        ):
            choices, note = configure.discover_models(
                "opencode-go-api", "existing-key"
            )

        list_models.assert_called_once_with("existing-key")
        self.assertEqual([choice.value for choice in choices], [
            "opencode-go/deepseek-v4-flash"
        ])
        self.assertEqual(choices[0].label, "deepseek-v4-flash")
        self.assertEqual(choices[0].reasoning_levels, ("low", "high", "max"))
        self.assertIn("Live model list", note)
        self.assertIn("Reasoning variants", note)

    def test_cancel_exits_without_saving(self) -> None:
        output = StringIO()
        output.isatty = lambda: True  # type: ignore[method-assign]
        with (
            mock.patch.object(configure.sys, "argv", ["configure.py"]),
            mock.patch.object(configure.sys.stdin, "isatty", return_value=True),
            mock.patch.object(configure.sys, "stdout", output),
            mock.patch.object(
                configure.curses, "wrapper", side_effect=configure.Cancelled
            ),
            mock.patch.object(configure, "save_state") as save_state,
        ):
            exit_code = configure.main()

        self.assertEqual(exit_code, 130)
        save_state.assert_not_called()

    def test_existing_config_defaults_to_updating_loaded_choices(self) -> None:
        existing = configure.SetupState(
            mode="pr-only",
            rebase=False,
            review=True,
            reviewers=["claude"],
            models={"claude": ["sonnet"]},
        )
        wizard = object.__new__(configure.Wizard)
        wizard.state = existing
        wizard.warning = ""
        wizard.existing_config = True
        calls: list[tuple[str, str]] = []

        def select_one(
            title: str,
            _choices: object,
            initial: str,
            **_kwargs: object,
        ) -> str:
            calls.append((title, initial))
            if title == "Existing configuration found":
                return "update"
            raise configure.Cancelled

        wizard.select_one = select_one

        with self.assertRaises(configure.Cancelled):
            wizard.run()

        self.assertEqual(calls[0], ("Existing configuration found", "update"))
        self.assertIs(wizard.state, existing)

    def test_starting_from_scratch_resets_the_state_that_will_be_saved(self) -> None:
        existing = configure.SetupState(
            mode="pr-only",
            rebase=False,
            review=True,
            reviewers=["claude"],
            models={"claude": ["sonnet"]},
        )
        wizard = object.__new__(configure.Wizard)
        wizard.state = existing
        wizard.warning = ""
        wizard.existing_config = True

        def select_one(title: str, *_args: object, **_kwargs: object) -> str:
            if title == "Existing configuration found":
                return "reset"
            raise configure.Cancelled

        wizard.select_one = select_one

        with self.assertRaises(configure.Cancelled):
            wizard.run()

        self.assertIs(wizard.state, existing)
        self.assertEqual(existing, configure.SetupState())

    def test_back_returns_to_previous_step_not_wizard_start(self) -> None:
        wizard = object.__new__(configure.Wizard)
        wizard.state = configure.SetupState()
        wizard.warning = ""
        wizard.existing_config = False
        calls: list[str] = []
        review_visits = 0

        def select_one(title: str, *_args: object, **_kwargs: object) -> str:
            nonlocal review_visits
            calls.append(title)
            if title == "Choose auto-backup behavior":
                return "device-only"
            if title == "Rebase on main before backup?":
                return "true"
            if title == "Run AI review for PR modes?":
                review_visits += 1
                if review_visits == 2:
                    raise configure.Cancelled
                return "true"
            raise AssertionError(title)

        def select_ordered(title: str, *_args: object, **_kwargs: object) -> None:
            calls.append(title)
            return None

        wizard.select_one = select_one
        wizard.select_ordered = select_ordered

        with self.assertRaises(configure.Cancelled):
            wizard.run()

        self.assertEqual(
            calls,
            [
                "Choose auto-backup behavior",
                "Rebase on main before backup?",
                "Run AI review for PR modes?",
                "Select and order reviewers",
                "Run AI review for PR modes?",
            ],
        )


if __name__ == "__main__":
    unittest.main()

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
            reviewers=["agy", "opencode-go-api"],
            models={
                "agy": ["gemini-3.7-flash-low"],
                "opencode-go-api": ["opencode-go/deepseek-v4-flash"],
            },
        )
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir, "config.local.toml")
            configure.atomic_write(path, configure.render_config(state), 0o600)
            loaded, warning = configure.load_state(path)

            self.assertEqual(warning, "")
            self.assertEqual(loaded, state)
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)

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
        ) as list_models:
            choices, note = configure.discover_models(
                "opencode-go-api", "existing-key"
            )

        list_models.assert_called_once_with("existing-key")
        self.assertEqual([choice.value for choice in choices], [
            "opencode-go/deepseek-v4-flash"
        ])
        self.assertIn("Live catalog", note)

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

    def test_back_returns_to_previous_step_not_wizard_start(self) -> None:
        wizard = object.__new__(configure.Wizard)
        wizard.state = configure.SetupState()
        wizard.warning = ""
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

#!/usr/bin/env python3
"""Offline tests for the direct OpenCode Go API adapter."""

from __future__ import annotations

import importlib.util
import json
import os
import stat
import tempfile
import unittest
from pathlib import Path
from unittest import mock


MODULE_PATH = Path(__file__).with_name("opencode_go.py")
SPEC = importlib.util.spec_from_file_location("opencode_go", MODULE_PATH)
assert SPEC and SPEC.loader
opencode_go = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(opencode_go)


class OpenCodeGoTests(unittest.TestCase):
    def test_extracts_sorted_prefixed_model_ids(self) -> None:
        models = opencode_go.parse_models(
            {
                "object": "list",
                "data": [
                    {"id": "muse-spark-1.2-contributor", "object": "model"},
                    {"id": "deepseek-v4-flash", "object": "model"},
                ],
            }
        )
        self.assertEqual(
            models,
            [
                "opencode-go/deepseek-v4-flash",
                "opencode-go/muse-spark-1.2-contributor",
            ],
        )

    def test_selects_documented_protocols(self) -> None:
        self.assertEqual(opencode_go.protocol_for_model("gpt-5.6-luna"), "responses")
        self.assertEqual(
            opencode_go.protocol_for_model("muse-spark-1.2-contributor"), "responses"
        )
        self.assertEqual(opencode_go.protocol_for_model("minimax-m3"), "anthropic")
        self.assertEqual(opencode_go.protocol_for_model("qwen3.7-plus"), "anthropic")
        self.assertEqual(opencode_go.protocol_for_model("deepseek-v4-flash"), "chat")

    def test_builds_protocol_specific_requests_without_key_in_body(self) -> None:
        request = opencode_go.build_request(
            "deepseek-v4-flash", "review this", "secret-key", 4096
        )
        self.assertTrue(request.full_url.endswith("/chat/completions"))
        self.assertEqual(request.get_header("Authorization"), "Bearer secret-key")
        self.assertEqual(
            request.get_header("User-agent"), "dotfiles-auto-backup/1.0"
        )
        self.assertNotIn(b"secret-key", request.data)

        request = opencode_go.build_request(
            "minimax-m3", "review this", "secret-key", 4096
        )
        self.assertTrue(request.full_url.endswith("/messages"))
        self.assertEqual(request.get_header("X-api-key"), "secret-key")
        self.assertEqual(request.get_header("Anthropic-version"), "2023-06-01")

    def test_model_catalog_uses_non_blocked_user_agent(self) -> None:
        with mock.patch.object(opencode_go, "api_request", return_value={
            "data": [{"id": "deepseek-v4-flash"}]
        }) as request:
            opencode_go.list_models("secret-key")
        sent_request = request.call_args.args[0]
        self.assertEqual(
            sent_request.get_header("User-agent"), "dotfiles-auto-backup/1.0"
        )
        self.assertTrue(sent_request.get_header("X-opencode-session"))

    def test_every_request_carries_one_stable_session_id(self) -> None:
        opencode_go.session_id.cache_clear()
        with mock.patch.dict(os.environ, {}, clear=False):
            os.environ.pop(opencode_go.SESSION_ENV_KEY, None)
            first = opencode_go.build_request(
                "deepseek-v4-flash", "review this", "secret-key", 4096
            ).get_header("X-opencode-session")
            second = opencode_go.build_request(
                "minimax-m3", "review this", "secret-key", 4096
            ).get_header("X-opencode-session")
            with mock.patch.object(opencode_go, "api_request", return_value={
                "data": [{"id": "deepseek-v4-flash"}]
            }) as request:
                opencode_go.list_models("secret-key")
            catalog = request.call_args.args[0].get_header("X-opencode-session")

        self.assertTrue(first)
        self.assertEqual(first, second)
        self.assertEqual(first, catalog)

    def test_session_id_can_be_pinned_by_the_caller(self) -> None:
        opencode_go.session_id.cache_clear()
        self.addCleanup(opencode_go.session_id.cache_clear)
        with mock.patch.dict(
            os.environ, {opencode_go.SESSION_ENV_KEY: "  pinned-session  "}
        ):
            self.assertEqual(opencode_go.session_id(), "pinned-session")

    def test_blank_pinned_session_id_falls_back_to_a_generated_one(self) -> None:
        opencode_go.session_id.cache_clear()
        self.addCleanup(opencode_go.session_id.cache_clear)
        with mock.patch.dict(os.environ, {opencode_go.SESSION_ENV_KEY: "   "}):
            self.assertTrue(opencode_go.session_id().strip())

    def test_extracts_text_from_all_documented_protocols(self) -> None:
        fixtures = (
            ("responses", {"output_text": "APPROVED"}),
            (
                "chat",
                {"choices": [{"message": {"content": "CHANGES_REQUESTED"}}]},
            ),
            ("anthropic", {"content": [{"type": "text", "text": "APPROVED"}]}),
        )
        for protocol, payload in fixtures:
            with self.subTest(protocol=protocol):
                self.assertEqual(opencode_go.extract_text(protocol, payload), next(
                    text
                    for text in ("APPROVED", "CHANGES_REQUESTED")
                    if text in json.dumps(payload)
                ))

    def test_reads_only_owner_only_opencode_key_assignment(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            env_file = Path(temp_dir, ".env")
            env_file.write_text(
                "# OpenCode Go only\nOPENCODE_GO_API_KEY='secret-key'\n",
                encoding="utf-8",
            )
            env_file.chmod(stat.S_IRUSR | stat.S_IWUSR)
            self.assertEqual(opencode_go.read_env_key(env_file), "secret-key")

            env_file.write_text(
                "OPENCODE_GO_API_KEY=secret-key\nOTHER_SECRET=nope\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(opencode_go.AdapterError, "unsupported"):
                opencode_go.read_env_key(env_file)

            env_file.write_text("OPENCODE_GO_API_KEY=secret-key\n", encoding="utf-8")
            env_file.chmod(0o644)
            with self.assertRaisesRegex(opencode_go.AdapterError, "0600"):
                opencode_go.read_env_key(env_file)

    def test_errors_never_expose_api_key(self) -> None:
        error = opencode_go.AdapterError("request failed for secret-key")
        with mock.patch.dict(os.environ, {"OPENCODE_GO_API_KEY": "secret-key"}):
            self.assertNotIn("secret-key", opencode_go.safe_error(error))

    def test_validation_respects_provider_minimum_output_tokens(self) -> None:
        with (
            mock.patch.object(
                opencode_go.sys,
                "argv",
                ["opencode_go.py", "validate", "opencode-go/gpt-5.6-luna"],
            ),
            mock.patch.dict(os.environ, {"OPENCODE_GO_API_KEY": "secret-key"}),
            mock.patch.object(opencode_go, "run_inference", return_value="OK") as run,
        ):
            opencode_go.main()

        self.assertEqual(run.call_args.args[-1], 16)


if __name__ == "__main__":
    unittest.main()

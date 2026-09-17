#!/usr/bin/env python3
"""Offline tests for auto-backup review input preparation and coverage checks."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("review_diff.py")
SPEC = importlib.util.spec_from_file_location("review_diff", MODULE_PATH)
assert SPEC and SPEC.loader
review_diff = importlib.util.module_from_spec(SPEC)
# dataclasses resolves string annotations through sys.modules.
sys.modules[SPEC.name] = review_diff
SPEC.loader.exec_module(review_diff)


def extension(ext_id: str, version: str, **extra: object) -> dict[str, object]:
    entry: dict[str, object] = {
        "identifier": {"id": ext_id},
        "version": version,
        "location": {"path": f"${{HOME}}/.vscode/extensions/{ext_id}-{version}"},
        "metadata": {"installedTimestamp": 1789400000000},
    }
    entry.update(extra)
    return entry


def profile(*entries: dict[str, object]) -> list[dict[str, object]]:
    """A VS Code profile large enough to be stored as one long JSON line."""
    return [extension(f"filler.ext-{index}", "1.0.0") for index in range(60)] + list(entries)


def single_line_json_diff(path: str, old_text: str, new_text: str) -> str:
    return "\n".join(
        [
            f"diff --git a/{path} b/{path}",
            "index 1111111..2222222 100644",
            f"--- a/{path}",
            f"+++ b/{path}",
            "@@ -1 +1 @@",
            "-" + old_text,
            "\\ No newline at end of file",
            "+" + new_text,
            "\\ No newline at end of file",
        ]
    ) + "\n"


SETTINGS_DIFF = """diff --git a/apps/editors/vscode/settings.json b/apps/editors/vscode/settings.json
index 06b4a02..ee6359a 100644
--- a/apps/editors/vscode/settings.json
+++ b/apps/editors/vscode/settings.json
@@ -32,3 +32,3 @@
   "editor.fontFamily": "Geist Mono",
-  "editor.fontSize": 15,
+  "editor.fontSize": 15.5,
   "editor.fontWeight": "400",
"""

PROFILE_PATH = "apps/editors/vscode/profiles/5a14b135/extensions.json"


class PrepareTests(unittest.TestCase):
    def test_single_line_json_rewrite_becomes_structural_diff(self) -> None:
        old = profile(extension("tldraw-org.tldraw-vscode", "2.352.0"))
        new = profile(extension("tldraw-org.tldraw-vscode", "2.353.0"))
        raw = single_line_json_diff(PROFILE_PATH, json.dumps(old), json.dumps(new))

        review_input, paths = review_diff.prepare(raw)

        self.assertEqual(paths, [PROFILE_PATH])
        self.assertIn(
            '~ $[identifier.id="tldraw-org.tldraw-vscode"].version: "2.352.0" -> "2.353.0"',
            review_input,
        )
        self.assertIn(f"- M {PROFILE_PATH} (+1/-1, structural JSON diff)", review_input)
        self.assertNotIn("filler.ext-0", review_input)
        self.assertLess(len(review_input), len(raw) // 5)

    def test_added_and_removed_entries_keep_their_full_values(self) -> None:
        added = extension("new.publisher-ext", "0.1.0", custom={"endpoint": "https://example.invalid/hook"})
        removed = extension("old.publisher-ext", "3.0.0")
        raw = single_line_json_diff(
            PROFILE_PATH, json.dumps(profile(removed)), json.dumps(profile(added))
        )

        review_input, _ = review_diff.prepare(raw)

        self.assertIn(f'+ $[identifier.id="new.publisher-ext"]: {json.dumps(added)}', review_input)
        self.assertIn(f'- $[identifier.id="old.publisher-ext"]: {json.dumps(removed)}', review_input)

    def test_reordered_entries_are_reported(self) -> None:
        first = extension("a.first", "1.0.0")
        second = extension("b.second", "1.0.0")
        raw = single_line_json_diff(
            PROFILE_PATH, json.dumps(profile(first, second)), json.dumps(profile(second, first))
        )

        review_input, _ = review_diff.prepare(raw)

        self.assertIn("~ $: shared entries reordered", review_input)

    def test_corrupted_json_keeps_raw_diff_for_the_reviewer(self) -> None:
        old_text = json.dumps(profile())
        truncated = old_text[: len(old_text) // 2]
        raw = single_line_json_diff(PROFILE_PATH, old_text, truncated)

        review_input, _ = review_diff.prepare(raw)

        self.assertIn("+" + truncated, review_input)
        self.assertNotIn("structural JSON diff", review_input)

    def test_short_multi_line_diff_is_unchanged(self) -> None:
        review_input, paths = review_diff.prepare(SETTINGS_DIFF)

        self.assertEqual(paths, ["apps/editors/vscode/settings.json"])
        self.assertIn(SETTINGS_DIFF, review_input)
        self.assertIn("- M apps/editors/vscode/settings.json (+1/-1)", review_input)

    def test_manifest_reports_added_deleted_renamed_and_binary_files(self) -> None:
        raw = "".join(
            [
                "diff --git a/cli/new.conf b/cli/new.conf\nnew file mode 100644\n"
                "index 0000000..1111111\n--- /dev/null\n+++ b/cli/new.conf\n@@ -0,0 +1 @@\n+a=1\n",
                "diff --git a/cli/old.conf b/cli/old.conf\ndeleted file mode 100644\n"
                "index 1111111..0000000\n--- a/cli/old.conf\n+++ /dev/null\n@@ -1 +0,0 @@\n-a=1\n",
                "diff --git a/fonts/a.txt b/fonts/b.txt\nsimilarity index 100%\n"
                "rename from fonts/a.txt\nrename to fonts/b.txt\n",
                "diff --git a/fonts/My Font.ttf b/fonts/My Font.ttf\nindex 1111111..2222222 100644\n"
                "Binary files a/fonts/My Font.ttf and b/fonts/My Font.ttf differ\n",
            ]
        )

        review_input, paths = review_diff.prepare(raw)

        self.assertEqual(paths, ["cli/new.conf", "cli/old.conf", "fonts/b.txt", "fonts/My Font.ttf"])
        self.assertTrue(review_input.startswith("# Changed files (4)\n"))
        for line in (
            "- A cli/new.conf (+1/-0)",
            "- D cli/old.conf (+0/-1)",
            "- R fonts/b.txt (+0/-0)",
            "- M fonts/My Font.ttf (+0/-0)",
        ):
            self.assertIn(line, review_input)


# The body AGY gemini-3.1-pro-high wrote for PR #288, which reported
# "5 files reviewed" for a 16-file PR and was auto-merged.
PR_288_PATHS = [
    "apps/ai-tools/codex/config.toml",
    "apps/editors/cursor/settings.json",
    "apps/editors/vscode/profiles/-1f8533fc/extensions.json",
    "apps/editors/vscode/profiles/-26085c9b/extensions.json",
    "apps/editors/vscode/profiles/-399f5ae0/extensions.json",
    "apps/editors/vscode/profiles/-3e2a37fe/extensions.json",
    "apps/editors/vscode/profiles/-7b5daf16/extensions.json",
    "apps/editors/vscode/profiles/-9baf489d/extensions.json",
    "apps/editors/vscode/profiles/5a14b135/extensions.json",
    "apps/editors/vscode/profiles/677f0f3b/extensions.json",
    "apps/editors/vscode/profiles/68347f39/extensions.json",
    "apps/editors/vscode/settings.json",
    "apps/terminal/ghostty/config",
    "history/.zsh_history",
    "macos/defaults-snapshot.txt",
    "macos/defaults.sh",
]
PR_288_REVIEW = """APPROVED

### Important Files Changed

| Filename | Score | Overview |
|----------|-------|----------|
| `apps/ai-tools/codex/config.toml` | 5/5 | Minor adjustments to plugin toggles and font size settings. |
| `apps/editors/cursor/settings.json` | 5/5 | Minor editor font size configuration update. |
| `apps/editors/vscode/profiles/*/extensions.json` | 4/5 | Routine updates to installed extension metadata. |

5 files reviewed, 0 comments
"""


class CoverageTests(unittest.TestCase):
    def test_pr_288_review_is_reported_as_incomplete(self) -> None:
        self.assertEqual(
            review_diff.uncovered_paths(PR_288_PATHS, PR_288_REVIEW),
            [
                "apps/editors/vscode/settings.json",
                "apps/terminal/ghostty/config",
                "history/.zsh_history",
                "macos/defaults-snapshot.txt",
                "macos/defaults.sh",
            ],
        )

    def test_directory_globs_braces_and_markdown_links_cover_files(self) -> None:
        review = "\n".join(
            [
                "| [`apps/ai-tools/claude/rules/*`](file:///tmp/rules) (35 files) | 1/5 | Deleted |",
                "| **`apps/Brewfile`** | 5/5 | Added a cask. |",
                "| `macos/{defaults.sh,defaults-snapshot.txt}` | 5/5 | New defaults. |",
            ]
        )
        paths = [
            "apps/ai-tools/claude/rules/common/agents.md",
            "apps/Brewfile",
            "macos/defaults.sh",
            "macos/defaults-snapshot.txt",
        ]

        self.assertEqual(review_diff.uncovered_paths(paths, review), [])

    def test_longer_path_does_not_cover_its_prefix(self) -> None:
        review = "| `history/.zsh_history.bak` | 5/5 | Copy. |\n| `apps/Brewfile.lock.json` | 5/5 | Lock. |"

        self.assertEqual(
            review_diff.uncovered_paths(["history/.zsh_history", "apps/Brewfile"], review),
            ["history/.zsh_history", "apps/Brewfile"],
        )

    def test_coverage_command_prints_missing_paths_and_fails(self) -> None:
        with tempfile.TemporaryDirectory() as work_dir:
            paths_file = Path(work_dir, "paths")
            review_file = Path(work_dir, "review")
            paths_file.write_text("".join(path + "\n" for path in PR_288_PATHS), encoding="utf-8")
            review_file.write_text(PR_288_REVIEW, encoding="utf-8")

            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                status = review_diff.main(["coverage", str(paths_file), str(review_file)])
            self.assertEqual(status, 1)
            self.assertEqual(output.getvalue().splitlines()[0], "apps/editors/vscode/settings.json")

            review_file.write_text(PR_288_REVIEW + "\n".join(f"`{path}`" for path in PR_288_PATHS), encoding="utf-8")
            with contextlib.redirect_stdout(io.StringIO()):
                status = review_diff.main(["coverage", str(paths_file), str(review_file)])
            self.assertEqual(status, 0)


if __name__ == "__main__":
    unittest.main()

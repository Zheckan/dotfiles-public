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

        review_input, paths, _ = review_diff.prepare(raw)

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

        review_input, _, _ = review_diff.prepare(raw)

        self.assertIn(f'+ $[identifier.id="new.publisher-ext"]: {json.dumps(added)}', review_input)
        self.assertIn(f'- $[identifier.id="old.publisher-ext"]: {json.dumps(removed)}', review_input)

    def test_reordered_entries_are_reported(self) -> None:
        first = extension("a.first", "1.0.0")
        second = extension("b.second", "1.0.0")
        raw = single_line_json_diff(
            PROFILE_PATH, json.dumps(profile(first, second)), json.dumps(profile(second, first))
        )

        review_input, _, _ = review_diff.prepare(raw)

        self.assertIn("~ $: shared entries reordered", review_input)

    def test_corrupted_json_keeps_raw_diff_for_the_reviewer(self) -> None:
        old_text = json.dumps(profile())
        truncated = old_text[: len(old_text) // 2]
        raw = single_line_json_diff(PROFILE_PATH, old_text, truncated)

        review_input, _, _ = review_diff.prepare(raw)

        self.assertIn("+" + truncated, review_input)
        self.assertNotIn("structural JSON diff", review_input)

    def test_short_multi_line_diff_is_unchanged(self) -> None:
        review_input, paths, _ = review_diff.prepare(SETTINGS_DIFF)

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

        review_input, paths, _ = review_diff.prepare(raw)

        self.assertEqual(paths, ["cli/new.conf", "cli/old.conf", "fonts/b.txt", "fonts/My Font.ttf"])
        self.assertTrue(review_input.startswith("# Changed files (4)\n"))
        for line in (
            "- A cli/new.conf (+1/-0)",
            "- D cli/old.conf (+0/-1)",
            "- R fonts/b.txt (+0/-0)",
            "- M fonts/My Font.ttf (+0/-0)",
        ):
            self.assertIn(line, review_input)


def vendored_tree_diff(count: int) -> str:
    """A backup that swept in a vendored tree, as PR #291 did with synced skills."""
    return "".join(
        "diff --git a/{p} b/{p}\nnew file mode 100644\n"
        "index 0000000..1111111\n--- /dev/null\n+++ b/{p}\n"
        "@@ -0,0 +1,3 @@\n+one\n+two\n+three\n".format(
            p=f"apps/ai-tools/claude/skills/synced/bucket/skill-{index}/SKILL.md"
        )
        for index in range(count)
    )


def batch_review(
    verdict: str,
    score: int,
    path: str,
    risks: str = "None identified.",
    issues: str = "None identified.",
) -> str:
    return "\n".join(
        [
            verdict,
            "",
            "### Summary",
            f"Reviewed {path}.",
            "",
            f"### Confidence Score: {score}/5",
            "Routine.",
            "",
            "### Important Files Changed",
            "",
            "| Filename | Score | Overview |",
            "|----------|-------|----------|",
            f"| {path} | {score}/5 | Fine. |",
            "",
            "1 files reviewed, 0 comments",
            "",
            "### Potential risks",
            risks,
            "",
            "### Issues",
            issues,
        ]
    )


class OversizedDiffTests(unittest.TestCase):
    def test_diff_under_the_limit_keeps_its_body(self) -> None:
        review_input, paths, oversized = review_diff.prepare(
            vendored_tree_diff(3), max_lines=100
        )

        self.assertFalse(oversized)
        self.assertEqual(len(paths), 3)
        self.assertIn("# Diff", review_input)
        self.assertIn("+one", review_input)

    def test_oversized_diff_keeps_the_manifest_and_drops_the_body(self) -> None:
        review_input, paths, oversized = review_diff.prepare(
            vendored_tree_diff(40), max_lines=100
        )

        self.assertTrue(oversized)
        self.assertEqual(len(paths), 40)
        # The manifest is the part a human needs: it names the tree that exploded.
        self.assertTrue(review_input.startswith("# Changed files (40)\n"))
        self.assertIn("skills/synced/bucket/skill-39/SKILL.md", review_input)
        self.assertIn("exceeds the 100-line review limit", review_input)
        # No reviewer should receive a body it can only partly read.
        self.assertNotIn("+one", review_input)

    def test_a_diff_that_fits_stays_one_batch_without_batch_headers(self) -> None:
        batches, oversized = review_diff.split_batches(
            vendored_tree_diff(3), batch_lines=100
        )

        self.assertFalse(oversized)
        self.assertEqual(len(batches), 1)
        self.assertNotIn("# Batch", batches[0][0])

    def test_batches_split_on_file_boundaries_and_cover_every_path(self) -> None:
        # 9 lines per file, so a 20-line budget takes two files per batch.
        batches, oversized = review_diff.split_batches(
            vendored_tree_diff(7), batch_lines=20
        )

        self.assertFalse(oversized)
        self.assertEqual([len(paths) for _, paths in batches], [2, 2, 2, 1])
        covered = [path for _, paths in batches for path in paths]
        self.assertEqual(len(covered), 7)
        self.assertEqual(len(set(covered)), 7)
        for index, (text, paths) in enumerate(batches, start=1):
            self.assertIn(f"# Batch {index} of 4", text)
            # Each batch's manifest holds it to the files it was actually given.
            self.assertIn(f"# Changed files ({len(paths)})", text)
            for path in paths:
                self.assertIn(path, text)

    def test_every_batch_shows_the_shape_of_the_whole_pr(self) -> None:
        # A synced tree split across batches looks like a handful of benign files
        # to each reviewer; only the whole-PR view shows 7 new files in one place.
        raw = vendored_tree_diff(7) + single_line_json_diff(
            "apps/editors/vscode/settings.json", '{"a": 1}', '{"a": 2}'
        )

        batches, _ = review_diff.split_batches(raw, batch_lines=20)

        self.assertGreater(len(batches), 1)
        for text, _ in batches:
            self.assertIn("# Whole PR: 8 files", text)
            self.assertIn(
                "- apps/ai-tools/claude/skills/synced/bucket/: 7 files (7 new)", text
            )
            self.assertIn("- apps/editors/vscode/: 1 file", text)

    def test_whole_pr_summary_lists_only_the_busiest_directories(self) -> None:
        raw = "".join(
            vendored_tree_diff(1).replace(
                "apps/ai-tools/claude/skills/synced/bucket/skill-0", f"dir-{index}"
            )
            for index in range(30)
        )

        batches, _ = review_diff.split_batches(raw, batch_lines=20)

        text = batches[0][0]
        self.assertEqual(text.count("/: 1 file"), review_diff.SHAPE_DIRECTORIES)
        self.assertIn(f"{30 - review_diff.SHAPE_DIRECTORIES} more directories", text)

    def test_a_file_larger_than_the_budget_becomes_its_own_batch(self) -> None:
        raw = single_line_json_diff(
            "apps/editors/vscode/settings.json", '{"a": 1}', '{"a": 2}'
        ) + vendored_tree_diff(1)

        batches, oversized = review_diff.split_batches(raw, batch_lines=2)

        self.assertFalse(oversized)
        self.assertEqual(len(batches), 2)
        self.assertEqual([len(paths) for _, paths in batches], [1, 1])

    def test_split_command_writes_one_input_and_paths_file_per_batch(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            diff_file = root / "diff"
            diff_file.write_text(vendored_tree_diff(7), encoding="utf-8")

            with contextlib.redirect_stdout(io.StringIO()) as out:
                status = review_diff.main(["split", str(diff_file), str(root / "batches")])

            self.assertEqual(status, 0)
            self.assertEqual(out.getvalue().strip(), "1")
            self.assertTrue((root / "batches" / "batch-001.input").exists())
            self.assertEqual(
                len((root / "batches" / "batch-001.paths").read_text().splitlines()), 7
            )

    def test_single_batch_review_passes_through_untouched(self) -> None:
        review = batch_review("APPROVED", 5, "`a.json`", risks="None identified.")

        self.assertEqual(review_diff.merge_reviews([review]), review)

    def test_one_batch_requesting_changes_decides_the_whole_pr(self) -> None:
        merged = review_diff.merge_reviews(
            [
                batch_review("APPROVED", 5, "`a.json`"),
                batch_review("CHANGES_REQUESTED", 2, "`b.json`", issues="Secret found."),
                batch_review("APPROVED", 4, "`c.json`"),
            ]
        )

        self.assertTrue(merged.startswith("CHANGES_REQUESTED\n"))
        self.assertIn("Secret found.", merged)
        # The lowest confidence wins, not an average that would hide the outlier.
        self.assertIn("### Confidence Score: 2/5", merged)

    def test_a_batch_without_a_clear_approval_blocks_the_merge(self) -> None:
        # The merged verdict gates auto-merge, so anything short of every batch
        # approving must request changes rather than default to approval.
        merged = review_diff.merge_reviews(
            [
                batch_review("APPROVED", 5, "`a.json`"),
                batch_review("LGTM", 5, "`b.json`"),
            ]
        )

        self.assertTrue(merged.startswith("CHANGES_REQUESTED\n"))

    def test_merge_keeps_every_file_row_and_sums_the_tally(self) -> None:
        merged = review_diff.merge_reviews(
            [
                batch_review("APPROVED", 5, "`a.json`"),
                batch_review("APPROVED", 5, "`b.json`"),
            ]
        )

        self.assertIn("| `a.json` | 5/5 | Fine. |", merged)
        self.assertIn("| `b.json` | 5/5 | Fine. |", merged)
        self.assertIn("2 files reviewed, 0 comments", merged)
        # One header row only, not one per batch.
        self.assertEqual(merged.count("|----------|-------|----------|"), 1)

    def test_merge_drops_none_identified_when_another_batch_found_something(self) -> None:
        merged = review_diff.merge_reviews(
            [
                batch_review("APPROVED", 5, "`a.json`", risks="None identified."),
                batch_review("APPROVED", 3, "`b.json`", risks="New PATH entry."),
            ]
        )

        risks = merged.split("### Potential risks")[1].split("### Issues")[0]
        self.assertIn("New PATH entry.", risks)
        self.assertNotIn("None identified.", risks)

    def test_prepare_command_reports_oversized_with_a_distinct_status(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            diff_file, output_file, paths_file = (
                root / "diff",
                root / "out",
                root / "paths",
            )
            diff_file.write_text(vendored_tree_diff(4000), encoding="utf-8")

            status = review_diff.main(
                ["prepare", str(diff_file), str(output_file), str(paths_file)]
            )

            self.assertEqual(status, review_diff.OVERSIZED_STATUS)
            # The files are still written, so the caller can report the manifest.
            self.assertIn("# Changed files (4000)", output_file.read_text(encoding="utf-8"))
            self.assertEqual(len(paths_file.read_text(encoding="utf-8").splitlines()), 4000)


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

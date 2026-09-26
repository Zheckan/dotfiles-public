#!/usr/bin/env python3
"""Prepare auto-backup PR diffs for AI review and check review coverage.

Some apps store a whole JSON document on one line (VS Code profile
extensions.json files run to ~70k characters), so a one-value change rewrites
the entire line. A routine backup touching a few profiles then produces a
~500 KB diff that times out fast reviewer models and leads slower ones to
review only part of the PR.

`prepare` replaces those hunks with a structural JSON diff and prepends a
manifest of every changed file. `coverage` prints manifest paths a review never
mentions, so review_pr can reject a partial review and try the next model.
"""

from __future__ import annotations

import codecs
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

# A changed line longer than this is a candidate for the structural JSON diff.
LONG_LINE_CHARS = 4000
# A review is split into batches of about this many diff lines. Batching is not
# only for diffs too big to send at once: a reviewer handed 8 files accounts for
# them, where one handed 200 skims. PR #288 was auto-merged on a review that
# reported "5 files reviewed" for a 16-file PR.
BATCH_DIFF_LINES = 1500
# Above this many lines the diff is not reviewed at all, batched or otherwise.
# The largest legitimate backup in this repo's history is 12,301 lines, so a
# diff past this size means a tool wrote a tree into a backed-up directory
# rather than that this much configuration changed. PR #291 reached 80,710 lines
# after claude.ai skill sync wrote 209 vendored files into the backup.
MAX_DIFF_LINES = 30000
# Directories listed in the whole-PR summary each batch carries.
SHAPE_DIRECTORIES = 20
# `split` exit status when the diff was too large to send to a reviewer.
OVERSIZED_STATUS = 3
# Keys tried, in order, to match list entries between the old and new versions.
LIST_IDENTITY_KEYS = (("identifier", "id"), ("id",), ("name",), ("key",))

USAGE = """usage:
  review_diff.py prepare DIFF_FILE OUTPUT_FILE PATHS_FILE
  review_diff.py split DIFF_FILE OUTPUT_DIR
  review_diff.py merge REVIEW_FILE [REVIEW_FILE...]
  review_diff.py coverage PATHS_FILE REVIEW_FILE"""


@dataclass
class FileDiff:
    lines: list[str] = field(default_factory=list)
    path: str = ""
    status: str = "M"
    added: int = 0
    removed: int = 0
    structural: bool = False


def unquote_git_path(value: str) -> str:
    value = value.rstrip("\t")
    if len(value) >= 2 and value.startswith('"') and value.endswith('"'):
        raw = codecs.escape_decode(value[1:-1].encode("utf-8"))[0]
        return raw.decode("utf-8", errors="backslashreplace")
    return value


def strip_prefix(value: str, prefix: str) -> str:
    return value[len(prefix) :] if value.startswith(prefix) else value


def header_path(header: str) -> str:
    """Path from `diff --git a/P b/P`, for sections without ---/+++ lines."""
    rest = header[len("diff --git ") :]
    quoted = re.fullmatch(r'"(?:[^"\\]|\\.)*" ("(?:[^"\\]|\\.)*")', rest)
    if quoted:
        return strip_prefix(unquote_git_path(quoted.group(1)), "b/")
    length = (len(rest) - len("a/ b/")) // 2
    if (
        length > 0
        and rest.startswith("a/")
        and rest[2 + length : 5 + length] == " b/"
        and rest[2 : 2 + length] == rest[5 + length :]
    ):
        return rest[2 : 2 + length]
    return rest.rsplit(" b/", 1)[-1]


def describe(file: FileDiff) -> None:
    old_path = new_path = rename_to = None
    in_hunk = False

    for line in file.lines[1:]:
        if line.startswith("@@"):
            in_hunk = True
        elif in_hunk:
            if line.startswith("+"):
                file.added += 1
            elif line.startswith("-"):
                file.removed += 1
        elif line.startswith("new file mode"):
            file.status = "A"
        elif line.startswith("deleted file mode"):
            file.status = "D"
        elif line.startswith("rename to "):
            file.status = "R"
            rename_to = line[len("rename to ") :]
        elif line.startswith("--- "):
            old_path = unquote_git_path(line[4:])
        elif line.startswith("+++ "):
            new_path = unquote_git_path(line[4:])

    if rename_to:
        file.path = unquote_git_path(rename_to)
    elif new_path and new_path != "/dev/null":
        file.path = strip_prefix(new_path, "b/")
    elif old_path and old_path != "/dev/null":
        file.path = strip_prefix(old_path, "a/")
    else:
        file.path = header_path(file.lines[0])


def split_files(diff_text: str) -> tuple[list[str], list[FileDiff]]:
    preamble: list[str] = []
    files: list[FileDiff] = []

    for line in diff_text.split("\n"):
        if line.startswith("diff --git "):
            files.append(FileDiff(lines=[line]))
        elif files:
            files[-1].lines.append(line)
        else:
            preamble.append(line)

    for file in files:
        describe(file)
    return preamble, files


def canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, ensure_ascii=False)


def render(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False)


def key_segment(key: str) -> str:
    if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_-]*", key):
        return "." + key
    return "[" + render(key) + "]"


def lookup(item: Any, keys: tuple[str, ...]) -> Any:
    for key in keys:
        if not isinstance(item, dict) or key not in item:
            return None
        item = item[key]
    return item


def has_unique_identities(items: list[Any], keys: tuple[str, ...]) -> bool:
    seen = set()
    for item in items:
        value = lookup(item, keys)
        if isinstance(value, bool) or not isinstance(value, (str, int)) or value in seen:
            return False
        seen.add(value)
    return True


def list_identity(old: list[Any], new: list[Any]) -> tuple[str, ...] | None:
    for keys in LIST_IDENTITY_KEYS:
        if has_unique_identities(old, keys) and has_unique_identities(new, keys):
            return keys
    return None


def diff_keyed_list(
    old: list[Any], new: list[Any], keys: tuple[str, ...], path: str, out: list[str]
) -> None:
    label = ".".join(keys)
    old_items = {lookup(item, keys): item for item in old}
    new_items = {lookup(item, keys): item for item in new}

    def child(identity: Any) -> str:
        return f"{path}[{label}={render(identity)}]"

    for identity, item in old_items.items():
        if identity in new_items:
            diff_json(item, new_items[identity], child(identity), out)
        else:
            out.append(f"- {child(identity)}: {render(item)}")
    for identity, item in new_items.items():
        if identity not in old_items:
            out.append(f"+ {child(identity)}: {render(item)}")

    shared_old = [identity for identity in old_items if identity in new_items]
    shared_new = [identity for identity in new_items if identity in old_items]
    if shared_old != shared_new:
        out.append(f"~ {path}: shared entries reordered")


def diff_json(old: Any, new: Any, path: str, out: list[str]) -> None:
    """Append one line per added (+), removed (-), or changed (~) value."""
    if canonical(old) == canonical(new):
        return

    if isinstance(old, dict) and isinstance(new, dict):
        for key, value in old.items():
            if key in new:
                diff_json(value, new[key], path + key_segment(key), out)
            else:
                out.append(f"- {path}{key_segment(key)}: {render(value)}")
        for key, value in new.items():
            if key not in old:
                out.append(f"+ {path}{key_segment(key)}: {render(value)}")
        return

    if isinstance(old, list) and isinstance(new, list):
        keys = list_identity(old, new)
        if keys is not None:
            diff_keyed_list(old, new, keys, path, out)
            return
        if len(old) == len(new):
            for index, (old_item, new_item) in enumerate(zip(old, new)):
                diff_json(old_item, new_item, f"{path}[{index}]", out)
            return

    out.append(f"~ {path}: {render(old)} -> {render(new)}")


def compact_single_line_json(file: FileDiff) -> None:
    """Swap a single-line JSON rewrite for a structural diff of its values.

    Only applies when both sides parse, so a corrupted file keeps its raw diff
    in front of the reviewer.
    """
    first_hunk = next(
        (index for index, line in enumerate(file.lines) if line.startswith("@@")), None
    )
    if first_hunk is None:
        return

    body = file.lines[first_hunk:]
    removed = [line[1:] for line in body if line.startswith("-")]
    added = [line[1:] for line in body if line.startswith("+")]
    if len(removed) != 1 or len(added) != 1:
        return
    if max(len(removed[0]), len(added[0])) <= LONG_LINE_CHARS:
        return
    try:
        old = json.loads(removed[0])
        new = json.loads(added[0])
    except ValueError:
        return

    changes: list[str] = []
    diff_json(old, new, "$", changes)
    count = f"{len(changes)} change" + ("" if len(changes) == 1 else "s")
    block = [
        f"@@ structural JSON diff: {count} @@",
        f"# This file is one line of JSON (old {len(removed[0]):,} chars, new {len(added[0]):,} chars).",
        "# Both versions parse as valid JSON. Every added (+), removed (-), and changed (~)",
        "# value is listed below; anything not listed is unchanged.",
    ]
    block += changes or ["# No values changed (formatting or key order only)."]

    trailing = [""] if file.lines[-1] == "" else []
    file.lines = file.lines[:first_hunk] + block + trailing
    file.structural = True


def manifest(files: list[FileDiff]) -> list[str]:
    lines = [f"# Changed files ({len(files)})", ""]
    for file in files:
        note = ", structural JSON diff" if file.structural else ""
        lines.append(f"- {file.status} {file.path} (+{file.added}/-{file.removed}{note})")
    return lines


def plural(count: int, noun: str) -> str:
    return f"{count} {noun}" if count == 1 else f"{count} {noun}s"


def pr_shape(files: list[FileDiff], total_lines: int, batch_count: int) -> list[str]:
    """Summarizes the whole PR by directory for a reviewer that sees one batch.

    A synced tree split across batches looks like a few benign files to each
    reviewer. Only the whole-PR view shows dozens of new files under one
    directory, which is the signal the review prompt tells reviewers to act on.
    """
    # Count every ancestor, since a synced tree spreads one file per skill
    # directory and only a shared ancestor like `skills/synced/` shows its size.
    counts: dict[str, list[int]] = {}
    for file in files:
        parts = file.path.split("/")[:-1]
        for depth in range(1, len(parts) + 1):
            entry = counts.setdefault("/".join(parts[:depth]) + "/", [0, 0])
            entry[0] += 1
            entry[1] += file.status == "A"

    # An ancestor holding exactly the files of one child says nothing new.
    redundant = set()
    for directory, (count, _) in counts.items():
        parent = directory[:-1].rpartition("/")[0]
        if parent and counts[parent + "/"][0] == count:
            redundant.add(parent + "/")

    ranked = sorted(
        ((d, c) for d, c in counts.items() if d not in redundant),
        key=lambda item: (-item[1][0], item[0]),
    )
    lines = [
        f"# Whole PR: {plural(len(files), 'file')}, {total_lines} diff lines,"
        f" {batch_count} batches",
        "",
        "Context only, for patterns no single batch can show, such as a synced"
        " third-party tree. Your file table covers this batch's manifest, not this list.",
        "",
    ]
    for directory, (count, added) in ranked[:SHAPE_DIRECTORIES]:
        note = f" ({added} new)" if added else ""
        lines.append(f"- {directory}: {plural(count, 'file')}{note}")
    if len(ranked) > SHAPE_DIRECTORIES:
        lines.append(f"- … {len(ranked) - SHAPE_DIRECTORIES} more directories")
    return lines + [""]


def pack(files: list[FileDiff], batch_lines: int) -> list[list[FileDiff]]:
    """Groups files into batches without ever splitting one file across two.

    A reviewer that sees half a file cannot judge it, so a file whose own diff
    exceeds the budget becomes a batch by itself rather than being cut.
    """
    groups: list[list[FileDiff]] = []
    current: list[FileDiff] = []
    used = 0
    for file in files:
        size = len(file.lines)
        if current and used + size > batch_lines:
            groups.append(current)
            current, used = [], 0
        current.append(file)
        used += size
    if current:
        groups.append(current)
    return groups


def prepare(diff_text: str, max_lines: int = MAX_DIFF_LINES) -> tuple[str, list[str], bool]:
    """Returns one reviewer input covering the whole diff, and whether it was too large.

    An oversized diff keeps its manifest and drops the body: the manifest is what
    a human needs to see which tree exploded, and no reviewer should be asked to
    approve a diff it can only partly read.
    """
    batches, oversized = split_batches(diff_text, batch_lines=max_lines, max_lines=max_lines)
    text, paths = batches[0]
    return text, paths, oversized


def split_batches(
    diff_text: str,
    batch_lines: int = BATCH_DIFF_LINES,
    max_lines: int = MAX_DIFF_LINES,
) -> tuple[list[tuple[str, list[str]]], bool]:
    """Returns the per-batch reviewer inputs and whether the diff was too large.

    Each batch carries its own manifest, so the coverage check holds every batch
    to the files it was actually given.
    """
    preamble, files = split_files(diff_text)
    for file in files:
        compact_single_line_json(file)

    total = len(preamble) + sum(len(file.lines) for file in files)
    if total > max_lines:
        note = [
            "",
            f"# Diff omitted: {total} lines exceeds the {max_lines}-line review limit",
            "",
        ]
        return [("\n".join(manifest(files) + note), [file.path for file in files])], True

    groups = pack(files, batch_lines) or [[]]
    shape = pr_shape(files, total, len(groups)) if len(groups) > 1 else []
    batches: list[tuple[str, list[str]]] = []
    for index, group in enumerate(groups, start=1):
        header: list[str] = []
        if len(groups) > 1:
            header = [
                f"# Batch {index} of {len(groups)}",
                "",
                "This is one part of a larger PR, split so every file gets read. Review"
                " only the files in the manifest below; the other batches are covered"
                " separately.",
                "",
                *shape,
            ]
        body = (preamble if index == 1 else []) + [line for file in group for line in file.lines]
        batches.append(
            (
                "\n".join(header + manifest(group) + ["", "# Diff", ""] + body),
                [file.path for file in group],
            )
        )
    return batches, False


def sections(review: str) -> tuple[str, dict[str, list[str]]]:
    """Splits a review into its verdict and its `### ` sections."""
    lines = review.split("\n")
    verdict = lines[0].strip() if lines else ""
    found: dict[str, list[str]] = {}
    name = ""
    for line in lines[1:]:
        if line.startswith("### "):
            name = line[4:].strip()
            found.setdefault(name, [])
        elif name:
            found[name].append(line)
    return verdict, found


def section_body(found: dict[str, list[str]], prefix: str) -> list[str]:
    for name, body in found.items():
        if name.lower().startswith(prefix.lower()):
            return body
    return []


def merge_reviews(reviews: list[str]) -> str:
    """Combines per-batch reviews into one body.

    A batch that requests changes decides the whole PR: each batch saw a
    different slice, so the one that found a problem is the one with evidence.
    """
    if len(reviews) == 1:
        return reviews[0]

    parsed = [sections(review) for review in reviews]
    # This verdict gates auto-merge, so approval must be unanimous and explicit.
    verdict = (
        "APPROVED"
        if all(v == "APPROVED" for v, _ in parsed)
        else "CHANGES_REQUESTED"
    )

    summaries: list[str] = []
    scores: list[int] = []
    rows: list[str] = []
    risks: list[str] = []
    issues: list[str] = []
    reviewed = comments = 0

    for index, (_, found) in enumerate(parsed, start=1):
        text = " ".join(line.strip() for line in section_body(found, "Summary")).strip()
        if text:
            summaries.append(f"**Batch {index}.** {text}")

        for name in found:
            match = re.search(r"Confidence Score:\s*(\d+)\s*/\s*5", name)
            if match:
                scores.append(int(match.group(1)))

        for line in section_body(found, "Important Files Changed"):
            stripped = line.strip()
            if stripped.startswith("|") and not re.fullmatch(r"\|[\s|:-]+\|", stripped):
                if not re.match(r"\|\s*Filename\s*\|", stripped):
                    rows.append(stripped)
            tally = re.search(r"(\d+)\s+files? reviewed,\s*(\d+)\s+comments?", stripped)
            if tally:
                reviewed += int(tally.group(1))
                comments += int(tally.group(2))

        for prefix, bucket in (("Potential risks", risks), ("Issues", issues)):
            body = " ".join(line.strip() for line in section_body(found, prefix)).strip()
            if body and body.lower().rstrip(".") != "none identified":
                bucket.append(f"**Batch {index}.** {body}")

    score = min(scores) if scores else 1
    return "\n".join(
        [
            verdict,
            "",
            "### Summary",
            f"Reviewed in {len(reviews)} batches so every file was read in full.",
            "",
            *summaries,
            "",
            f"### Confidence Score: {score}/5",
            f"Lowest score across {len(reviews)} batches.",
            "",
            "### Important Files Changed",
            "",
            "| Filename | Score | Overview |",
            "|----------|-------|----------|",
            *rows,
            "",
            f"{reviewed} files reviewed, {comments} comments",
            "",
            "### Potential risks",
            *(risks or ["None identified."]),
            "",
            "### Issues",
            *(issues or ["None identified."]),
        ]
    )


def glob_regex(pattern: str) -> re.Pattern[str]:
    """fnmatch-style: `*` crosses directories, so `rules/*` covers `rules/a/b.md`.

    Reviewers write `dir/*` to mean everything under a directory, and that is
    still an explicit account of those files. `{a,b}` alternatives are allowed.
    """
    parts: list[str] = []
    index = 0
    while index < len(pattern):
        char = pattern[index]
        if char == "*":
            parts.append(".*")
        elif char == "?":
            parts.append(".")
        elif char == "{" and pattern.find("}", index) > index:
            end = pattern.find("}", index)
            options = pattern[index + 1 : end].split(",")
            parts.append("(?:" + "|".join(re.escape(option) for option in options) + ")")
            index = end + 1
            continue
        else:
            parts.append(re.escape(char))
        index += 1
    return re.compile("".join(parts))


def mentions(path: str, text: str) -> bool:
    pattern = r"(?<![\w./-])" + re.escape(path) + r"(?![\w/-]|\.\w)"
    return re.search(pattern, text) is not None


def uncovered_paths(paths: list[str], review: str) -> list[str]:
    globs = [
        glob_regex(token.strip(".,:;"))
        for token in re.findall(r"[^\s`|()\[\]<>\"']+", review)
        if "/" in token and ("*" in token or "{" in token)
    ]
    return [
        path
        for path in paths
        if not mentions(path, review) and not any(glob.fullmatch(path) for glob in globs)
    ]


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv

    if len(args) == 4 and args[0] == "prepare":
        _, diff_file, output_file, paths_file = args
        with open(diff_file, "r", encoding="utf-8") as fh:
            review_input, paths, oversized = prepare(fh.read())
        with open(output_file, "w", encoding="utf-8") as fh:
            fh.write(review_input)
        with open(paths_file, "w", encoding="utf-8") as fh:
            fh.write("".join(path + "\n" for path in paths))
        return OVERSIZED_STATUS if oversized else 0

    if len(args) == 3 and args[0] == "split":
        _, diff_file, output_dir = args
        with open(diff_file, "r", encoding="utf-8") as fh:
            batches, oversized = split_batches(fh.read())
        directory = Path(output_dir)
        directory.mkdir(parents=True, exist_ok=True)
        for index, (text, paths) in enumerate(batches, start=1):
            stem = directory / f"batch-{index:03d}"
            stem.with_suffix(".input").write_text(text, encoding="utf-8")
            stem.with_suffix(".paths").write_text(
                "".join(path + "\n" for path in paths), encoding="utf-8"
            )
        print(len(batches))
        return OVERSIZED_STATUS if oversized else 0

    if len(args) >= 2 and args[0] == "merge":
        reviews = []
        for path in args[1:]:
            with open(path, "r", encoding="utf-8") as fh:
                reviews.append(fh.read().rstrip("\n"))
        print(merge_reviews(reviews))
        return 0

    if len(args) == 3 and args[0] == "coverage":
        _, paths_file, review_file = args
        with open(paths_file, "r", encoding="utf-8") as fh:
            paths = [line for line in fh.read().splitlines() if line]
        with open(review_file, "r", encoding="utf-8") as fh:
            missing = uncovered_paths(paths, fh.read())
        for path in missing:
            print(path)
        return 1 if missing else 0

    print(USAGE, file=sys.stderr)
    return 64


if __name__ == "__main__":
    sys.exit(main())

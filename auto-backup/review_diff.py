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
from typing import Any

# A changed line longer than this is a candidate for the structural JSON diff.
LONG_LINE_CHARS = 4000
# Keys tried, in order, to match list entries between the old and new versions.
LIST_IDENTITY_KEYS = (("identifier", "id"), ("id",), ("name",), ("key",))

USAGE = """usage:
  review_diff.py prepare DIFF_FILE OUTPUT_FILE PATHS_FILE
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


def prepare(diff_text: str) -> tuple[str, list[str]]:
    preamble, files = split_files(diff_text)
    for file in files:
        compact_single_line_json(file)

    diff_lines = preamble + [line for file in files for line in file.lines]
    review_input = "\n".join(manifest(files) + ["", "# Diff", ""] + diff_lines)
    return review_input, [file.path for file in files]


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
            review_input, paths = prepare(fh.read())
        with open(output_file, "w", encoding="utf-8") as fh:
            fh.write(review_input)
        with open(paths_file, "w", encoding="utf-8") as fh:
            fh.write("".join(path + "\n" for path in paths))
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

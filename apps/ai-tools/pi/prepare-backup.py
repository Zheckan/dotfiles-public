#!/usr/bin/env python3
"""Prepare only reusable Pi configuration. Never write directly to the snapshot."""
from __future__ import annotations

import json
from pathlib import Path
import re
import shutil
import sys
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

FILES = (
    "settings.json", "keybindings.json", "models.json", "mcp.json",
    "AGENTS.override.md", "AGENTS.md", "AGENTS.MD", "CLAUDE.md", "CLAUDE.MD",
    "SYSTEM.md", "APPEND_SYSTEM.md",
)
DIRECTORIES = ("extensions", "skills", "prompts", "themes", "tests")
EXCLUDED = {
    ".DS_Store", ".git", "node_modules", "__pycache__", ".venv", "venv",
    "auth.json", "mcp-auth.json", "trust.json", "models-store.json",
}


PLACEHOLDER = "REDACTED_SET_THIS_SECRET_ON_RESTORE"
SECRET_KEY = re.compile(r"api[_-]?key|token|secret|password|passwd|authorization|authentication|auth[_-]|[_-]auth|^auth$|bearer|credential|signature|^sig$|^key$", re.I)
ENV_REFERENCE = re.compile(r"^(?:(?:Bearer|Basic) )?(?:\$[A-Za-z_][A-Za-z0-9_]*|\$\{[A-Za-z_][A-Za-z0-9_]*\})$")
KNOWN_SECRET = re.compile(
    rb"(?:sk-(?:ant-|proj-|live-|test-)?|ctx7sk-|gh[pousr]_|github_pat_|xox[baprs]-)[A-Za-z0-9_-]{20,}"
    rb"|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----"
)


def check_resource(contents: bytes, name: str) -> None:
    if KNOWN_SECRET.search(contents):
        raise ValueError(f"possible credential in resource: {name}")


def secret_value(value: str) -> str:
    return value if not value or value == PLACEHOLDER or ENV_REFERENCE.fullmatch(value) else PLACEHOLDER


def redact_url(value: str) -> str:
    url = urlsplit(value)
    if url.scheme not in ("http", "https"):
        return value
    netloc = url.netloc
    if "@" in netloc:
        netloc = PLACEHOLDER + "@" + netloc.rsplit("@", 1)[1]
    query = parse_qsl(url.query, keep_blank_values=True)
    cleaned = [(key, secret_value(item) if SECRET_KEY.search(key) else item) for key, item in query]
    if netloc == url.netloc and cleaned == query:
        return value
    return urlunsplit((url.scheme, netloc, url.path, urlencode(cleaned), url.fragment))


def redact_arguments(arguments: list) -> list:
    result = []
    sensitive_next = False
    for argument in arguments:
        if not isinstance(argument, str):
            result.append(redact(argument))
            continue
        if sensitive_next:
            result.append(secret_value(argument))
            sensitive_next = False
            continue
        name, separator, value = argument.partition("=")
        is_header = name in ("-H", "--header", "--env", "-e")
        if SECRET_KEY.search(name) or is_header:
            if separator:
                result.append(name + "=" + secret_value(value))
            elif argument.startswith("-"):
                result.append(argument)
                sensitive_next = True
            else:
                result.append(secret_value(argument))
        else:
            result.append(redact(argument))
    return result


def redact(data, sensitive=False, named_entries=False):
    if isinstance(data, dict):
        result = {}
        for key, value in data.items():
            secret = sensitive or (not named_entries and bool(SECRET_KEY.search(key))) or key in ("env", "headers")
            # These maps contain package/model names, not credential field names.
            names = key in ("dependencies", "devDependencies", "peerDependencies", "optionalDependencies", "packages", "modelOverrides", "modelThinkingLevels")
            result[key] = redact_arguments(value) if key in ("args", "command", "npmCommand") and isinstance(value, list) and not secret else redact(value, secret, names)
        return result
    if isinstance(data, list):
        return [redact(value, sensitive) for value in data]
    if isinstance(data, str):
        if sensitive:
            return secret_value(data)
        if data.startswith(("http://", "https://")):
            return redact_url(data)
        if data.startswith(("git:http://", "git:https://")):
            return "git:" + redact_url(data[4:])
        # Shell prefixes and npm/git sources can also contain auth assignments.
        if re.search(r"(?i)(?:api[_-]?key|token|password|secret|authorization)\s*[=:]\s*\S+|\bBearer\s+\S+|--(?:api[_-]?key|token|password|secret)\s+\S+", data):
            return secret_value(data)
    return data


def copy_resource(source: Path, destination: Path) -> None:
    if source.name in EXCLUDED or source.name == ".env" or source.name.startswith(".env."):
        return
    if source.is_symlink():
        raise ValueError(f"symlink requires manual review: {source.name}")
    if source.is_dir():
        destination.mkdir(parents=True, exist_ok=True)
        for child in sorted(source.iterdir()):
            copy_resource(child, destination / child.name)
    elif source.is_file():
        destination.parent.mkdir(parents=True, exist_ok=True)
        if source.suffix == ".json":
            data = json.loads(source.read_text(encoding="utf-8-sig"))
            if source.name == "settings.json":
                data.pop("deviceId", None)
                data.pop("lastChangelogVersion", None)
            contents = (json.dumps(redact(data), indent=2, ensure_ascii=False) + "\n").encode("utf-8")
            check_resource(contents, source.name)
            destination.write_bytes(contents)
            shutil.copymode(source, destination)
        else:
            contents = source.read_bytes()
            check_resource(contents, source.name)
            # Copy the bytes we checked, not a second read of an actively edited file.
            destination.write_bytes(contents)
            shutil.copystat(source, destination)
    else:
        raise ValueError(f"unsupported resource: {source.name}")


def report_external_resources(settings: dict, source: Path) -> None:
    roots = [(source / name).resolve() for name in DIRECTORIES]
    for kind in ("extensions", "skills", "prompts", "themes", "packages"):
        for entry in settings.get(kind, []):
            path = entry.get("source", "") if isinstance(entry, dict) else entry
            if not isinstance(path, str) or path.startswith(("!", "-", "npm:", "git:", "http://", "https://", "builtin:")):
                continue
            path = path.removeprefix("+")
            resource = Path(path).expanduser()
            resource = (resource if resource.is_absolute() else source / resource).resolve()
            if any(resource == root or resource.is_relative_to(root) for root in roots):
                continue
            shared = (Path.home() / ".agents/skills").resolve()
            if kind == "skills" and (resource == shared or resource.is_relative_to(shared)):
                continue
            print(f"Pi {kind} entry points outside the snapshot; back up its source separately and check its path after restore.", file=sys.stderr)


def main(source: Path, destination: Path) -> None:
    for name in (*FILES, *DIRECTORIES):
        path = source / name
        if path.exists() or path.is_symlink():
            copy_resource(path, destination / name)
    settings_path = destination / "settings.json"
    if settings_path.exists():
        report_external_resources(json.loads(settings_path.read_text()), source)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: prepare-backup.py AGENT_DIR STAGING_DIR")
    try:
        main(Path(sys.argv[1]), Path(sys.argv[2]))
    except (OSError, ValueError, TypeError) as error:
        # JSON parse errors can quote live config. Never echo the failing value.
        print(f"Pi backup preparation failed ({type(error).__name__}); check config JSON and resource symlinks.", file=sys.stderr)
        raise SystemExit(1)

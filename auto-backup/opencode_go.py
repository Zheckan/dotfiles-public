#!/usr/bin/env python3
"""Direct, dependency-free adapter for the documented OpenCode Go API."""

from __future__ import annotations

import functools
import json
import os
import re
import stat
import sys
import urllib.error
import urllib.request
import uuid
from pathlib import Path
from typing import NoReturn


BASE_URL = "https://opencode.ai/zen/go/v1"
MODEL_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]*$")
ENV_KEY = "OPENCODE_GO_API_KEY"
# OpenCode's edge returns HTTP 403 to urllib's default Python-urllib user agent.
USER_AGENT = "dotfiles-auto-backup/1.0"
# OpenCode Go requires a stable session ID per conversation on every request.
SESSION_HEADER = "x-opencode-session"
SESSION_ENV_KEY = "OPENCODE_GO_SESSION_ID"
VALIDATION_MAX_TOKENS = 16


@functools.lru_cache(maxsize=1)
def session_id() -> str:
    """One stable session ID for every request this process makes.

    Each adapter run is a single-turn conversation, so a per-process ID is the
    right granularity. Callers that span several runs over one conversation can
    pin the ID through OPENCODE_GO_SESSION_ID.
    """
    return os.environ.get(SESSION_ENV_KEY, "").strip() or uuid.uuid4().hex


def default_headers() -> dict[str, str]:
    return {"User-Agent": USER_AGENT, SESSION_HEADER: session_id()}


class AdapterError(RuntimeError):
    """A safe-to-redact adapter failure."""


def fail(message: str) -> NoReturn:
    raise AdapterError(message)


def normalize_model(model: str) -> str:
    prefix = "opencode-go/"
    normalized = model[len(prefix) :] if model.startswith(prefix) else model
    if not MODEL_ID.fullmatch(normalized) or "/" in normalized:
        fail(f"invalid OpenCode Go model ID {model!r}")
    return normalized


def parse_models(payload: object) -> list[str]:
    if not isinstance(payload, dict) or not isinstance(payload.get("data"), list):
        fail("model catalog did not contain a data list")
    models: list[str] = []
    for entry in payload["data"]:
        if not isinstance(entry, dict) or not isinstance(entry.get("id"), str):
            fail("model catalog contained an invalid entry")
        model = normalize_model(entry["id"])
        models.append(f"opencode-go/{model}")
    if not models:
        fail("model catalog was empty")
    return sorted(set(models))


def protocol_for_model(model: str) -> str:
    model = normalize_model(model)
    if model.startswith(("grok-", "gpt-", "muse-")):
        return "responses"
    if model.startswith(("minimax-", "qwen")):
        return "anthropic"
    return "chat"


def build_request(
    model: str,
    prompt: str,
    api_key: str,
    max_tokens: int,
    *,
    base_url: str = BASE_URL,
) -> urllib.request.Request:
    model = normalize_model(model)
    protocol = protocol_for_model(model)
    headers = {"Content-Type": "application/json", **default_headers()}

    if protocol == "responses":
        endpoint = "responses"
        headers["Authorization"] = f"Bearer {api_key}"
        payload = {
            "model": model,
            "input": prompt,
            "max_output_tokens": max_tokens,
        }
    elif protocol == "anthropic":
        endpoint = "messages"
        headers["x-api-key"] = api_key
        headers["anthropic-version"] = "2023-06-01"
        payload = {
            "model": model,
            "max_tokens": max_tokens,
            "messages": [{"role": "user", "content": prompt}],
        }
    else:
        endpoint = "chat/completions"
        headers["Authorization"] = f"Bearer {api_key}"
        payload = {
            "model": model,
            "max_tokens": max_tokens,
            "messages": [{"role": "user", "content": prompt}],
        }

    return urllib.request.Request(
        f"{base_url.rstrip('/')}/{endpoint}",
        data=json.dumps(payload).encode("utf-8"),
        headers=headers,
        method="POST",
    )


def extract_text(protocol: str, payload: object) -> str:
    if not isinstance(payload, dict):
        fail("inference response was not a JSON object")

    text = ""
    if protocol == "responses":
        output_text = payload.get("output_text")
        if isinstance(output_text, str):
            text = output_text
        elif isinstance(payload.get("output"), list):
            parts: list[str] = []
            for item in payload["output"]:
                if not isinstance(item, dict) or not isinstance(item.get("content"), list):
                    continue
                for content in item["content"]:
                    if isinstance(content, dict) and isinstance(content.get("text"), str):
                        parts.append(content["text"])
            text = "\n".join(parts)
    elif protocol == "chat":
        choices = payload.get("choices")
        if isinstance(choices, list) and choices and isinstance(choices[0], dict):
            message = choices[0].get("message")
            if isinstance(message, dict):
                content = message.get("content")
                if isinstance(content, str):
                    text = content
                elif isinstance(content, list):
                    text = "\n".join(
                        part["text"]
                        for part in content
                        if isinstance(part, dict) and isinstance(part.get("text"), str)
                    )
    elif protocol == "anthropic":
        content = payload.get("content")
        if isinstance(content, list):
            text = "\n".join(
                part["text"]
                for part in content
                if isinstance(part, dict)
                and part.get("type") == "text"
                and isinstance(part.get("text"), str)
            )
    else:
        fail(f"unsupported response protocol {protocol!r}")

    if not text.strip():
        fail(f"{protocol} response contained no text")
    return text.strip()


def parse_json_response(response: object) -> object:
    try:
        return json.loads(response.read().decode("utf-8"))
    except (AttributeError, UnicodeDecodeError, json.JSONDecodeError) as error:
        fail(f"API returned invalid JSON: {error}")


def api_request(request: urllib.request.Request, *, timeout: int) -> object:
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return parse_json_response(response)
    except urllib.error.HTTPError as error:
        detail = f"HTTP {error.code}"
        try:
            payload = json.loads(error.read().decode("utf-8"))
            candidate = payload.get("error") if isinstance(payload, dict) else None
            if isinstance(candidate, dict):
                candidate = candidate.get("message")
            if isinstance(candidate, str) and candidate:
                detail = f"{detail}: {candidate}"
        except (UnicodeDecodeError, json.JSONDecodeError):
            pass
        fail(detail)
    except urllib.error.URLError as error:
        fail(f"network error: {error.reason}")


def list_models(api_key: str = "") -> list[str]:
    headers = {"Accept": "application/json", **default_headers()}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    request = urllib.request.Request(f"{BASE_URL}/models", headers=headers)
    return parse_models(api_request(request, timeout=30))


def run_inference(model: str, prompt: str, api_key: str, max_tokens: int) -> str:
    if not api_key:
        fail(f"{ENV_KEY} is not configured")
    request = build_request(model, prompt, api_key, max_tokens)
    payload = api_request(request, timeout=180)
    return extract_text(protocol_for_model(model), payload)


def read_env_key(path: Path) -> str:
    try:
        metadata = path.lstat()
    except FileNotFoundError:
        fail(f"secret file not found: {path}")
    except OSError as error:
        fail(f"cannot inspect secret file {path}: {error}")

    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        fail(f"{path} must be a regular file, not a symlink")
    if metadata.st_uid != os.getuid():
        fail(f"{path} must be owned by the current user")
    if stat.S_IMODE(metadata.st_mode) != 0o600:
        fail(f"{path} must have mode 0600")

    key = ""
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError) as error:
        fail(f"cannot read secret file {path}: {error}")

    for line_number, raw_line in enumerate(lines, 1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if not line.startswith(f"{ENV_KEY}="):
            fail(f"{path}:{line_number} contains an unsupported assignment")
        if key:
            fail(f"{path} contains duplicate {ENV_KEY} assignments")
        value = line.split("=", 1)[1].strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
            value = value[1:-1]
        elif any(character.isspace() for character in value):
            fail(f"{path}:{line_number} has an invalid unquoted value")
        if not value:
            fail(f"{ENV_KEY} must not be empty")
        key = value

    if not key:
        fail(f"{path} does not contain {ENV_KEY}")
    return key


def safe_error(error: BaseException) -> str:
    message = str(error)
    key = os.environ.get(ENV_KEY, "")
    if key:
        message = message.replace(key, "[REDACTED]")
    return message


def usage() -> NoReturn:
    fail(
        "usage: opencode_go.py models | read-key ENV_FILE | "
        "review MODEL PROMPT_FILE | validate MODEL"
    )


def main() -> None:
    if len(sys.argv) < 2:
        usage()
    command = sys.argv[1]

    if command == "models" and len(sys.argv) == 2:
        for model in list_models(os.environ.get(ENV_KEY, "")):
            print(model)
        return
    if command == "read-key" and len(sys.argv) == 3:
        print(read_env_key(Path(sys.argv[2])))
        return
    if command == "review" and len(sys.argv) == 4:
        try:
            prompt = Path(sys.argv[3]).read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as error:
            fail(f"cannot read review prompt: {error}")
        print(run_inference(sys.argv[2], prompt, os.environ.get(ENV_KEY, ""), 4096))
        return
    if command == "validate" and len(sys.argv) == 3:
        run_inference(
            sys.argv[2],
            "Reply with exactly OK.",
            os.environ.get(ENV_KEY, ""),
            VALIDATION_MAX_TOKENS,
        )
        return
    usage()


if __name__ == "__main__":
    try:
        main()
    except AdapterError as error:
        print(f"opencode_go.py: {safe_error(error)}", file=sys.stderr)
        raise SystemExit(2)

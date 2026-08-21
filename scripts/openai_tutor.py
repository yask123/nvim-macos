#!/usr/bin/env python3
"""Small stdin/stdout transport for Neovim Tutor.

The API key is read inside this process so it never appears in a command-line
argument. The request payload arrives on stdin and the response body is written
to stdout for the Lua UI to parse.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from typing import BinaryIO, Callable


API_URL = "https://api.openai.com/v1/responses"
MAX_BODY_BYTES = 2 * 1024 * 1024
TIMEOUT_SECONDS = 120


class TutorTransportError(RuntimeError):
    """An error safe to show without leaking request content or credentials."""


def _read_limited(stream: BinaryIO) -> bytes:
    body = stream.read(MAX_BODY_BYTES + 1)
    if len(body) > MAX_BODY_BYTES:
        raise TutorTransportError("OpenAI returned too much data.")
    return body


def post_response(
    payload: bytes,
    api_key: str,
    opener: Callable[..., BinaryIO] = urllib.request.urlopen,
) -> tuple[int, bytes]:
    request = urllib.request.Request(
        API_URL,
        data=payload,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        response = opener(request, timeout=TIMEOUT_SECONDS)
    except urllib.error.HTTPError as error:
        try:
            return error.code, _read_limited(error)
        finally:
            error.close()
    except (TimeoutError, urllib.error.URLError) as error:
        reason = getattr(error, "reason", None)
        if isinstance(reason, TimeoutError):
            raise TutorTransportError("The OpenAI request timed out.") from None
        raise TutorTransportError("Could not reach OpenAI.") from None

    try:
        status = getattr(response, "status", 200)
        return status, _read_limited(response)
    finally:
        response.close()


def main() -> int:
    api_key = os.environ.get("OPENAI_API_KEY", "")
    if not api_key:
        print("OPENAI_API_KEY is not set.", file=sys.stderr)
        return 2

    payload = sys.stdin.buffer.read(MAX_BODY_BYTES + 1)
    if len(payload) > MAX_BODY_BYTES:
        print("Tutor request is too large.", file=sys.stderr)
        return 2
    try:
        json.loads(payload)
    except (json.JSONDecodeError, UnicodeDecodeError):
        print("Tutor request is not valid JSON.", file=sys.stderr)
        return 2

    try:
        status, body = post_response(payload, api_key)
    except TutorTransportError as error:
        print(str(error), file=sys.stderr)
        return 1

    sys.stdout.buffer.write(body)
    return 0 if 200 <= status < 300 else 1


if __name__ == "__main__":
    raise SystemExit(main())

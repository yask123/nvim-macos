#!/usr/bin/env python3
"""Offline tests for the Tutor's OpenAI transport."""

from __future__ import annotations

import importlib.util
import io
import os
from pathlib import Path
import subprocess
import sys
import urllib.error


sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "scripts" / "openai_tutor.py"
SPEC = importlib.util.spec_from_file_location("openai_tutor", HELPER)
assert SPEC and SPEC.loader
openai_tutor = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(openai_tutor)


class FakeResponse(io.BytesIO):
    status = 200


seen: dict[str, object] = {}


def opener(request, timeout):
    seen["authorization"] = request.get_header("Authorization")
    seen["content_type"] = request.get_header("Content-type")
    seen["data"] = request.data
    seen["timeout"] = timeout
    return FakeResponse(b'{"status":"completed"}')


payload = b'{"model":"test"}'
status, body = openai_tutor.post_response(payload, "private-test-key", opener)
assert status == 200
assert body == b'{"status":"completed"}'
assert seen == {
    "authorization": "Bearer private-test-key",
    "content_type": "application/json",
    "data": payload,
    "timeout": 120,
}


def failing_opener(request, timeout):
    del request, timeout
    raise urllib.error.URLError("private network detail")


try:
    openai_tutor.post_response(payload, "private-test-key", failing_opener)
except openai_tutor.TutorTransportError as error:
    assert str(error) == "Could not reach OpenAI."
else:
    raise AssertionError("network errors must be sanitized")

env = os.environ.copy()
env.pop("OPENAI_API_KEY", None)
missing_key = subprocess.run(
    [sys.executable, str(HELPER)],
    input=b"{}",
    capture_output=True,
    check=False,
    env=env,
)
assert missing_key.returncode == 2
assert b"OPENAI_API_KEY is not set" in missing_key.stderr
assert b"{}" not in missing_key.stderr

print("OpenAI Tutor transport test passed")

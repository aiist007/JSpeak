#!/usr/bin/env python3

"""Quick manual client for jsp_speech_service.py.

Examples:

  python3 Python/jsp_test_client.py ping
  python3 Python/jsp_test_client.py capabilities

  # Transcribe a 16kHz mono wav using stream protocol:
  python3 Python/jsp_test_client.py stream_wav path/to/16k_mono.wav

  # Prefer Chinese (default):
  python3 Python/jsp_test_client.py --language zh stream_wav path/to/16k_mono.wav

  # Mixed Chinese+English (auto language detection):
  python3 Python/jsp_test_client.py --mixed stream_wav path/to/16k_mono.wav
"""

import base64
import json
import subprocess
import sys
import uuid
import wave


def _service_path() -> str:
    # Resolve relative to this file so it works from any cwd.
    import os

    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(here, "jsp_speech_service.py")


SERVICE = _service_path()


def req(method, params=None):
    return {"id": str(uuid.uuid4()), "method": method, "params": params or {}}


def parse_flags(argv):
    mixed = False
    language = None
    i = 1
    while i < len(argv) and argv[i].startswith("--"):
        if argv[i] == "--mixed":
            mixed = True
            i += 1
            continue
        if argv[i] == "--language" and i + 1 < len(argv):
            language = argv[i + 1]
            i += 2
            continue
        break
    return mixed, language, i


def run_one(r):
    p = subprocess.Popen(
        [sys.executable, SERVICE],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        text=True,
    )
    if p.stdin is None or p.stdout is None:
        raise RuntimeError("Failed to open subprocess pipes")
    p.stdin.write(json.dumps(r) + "\n")
    p.stdin.flush()
    line = p.stdout.readline().strip()
    if not line:
        p.terminate()
        raise RuntimeError("No response from service")
    p.terminate()
    return json.loads(line)


def stream_wav(path, mixed: bool, language):
    with wave.open(path, "rb") as w:
        if w.getnchannels() != 1:
            raise SystemExit("wav must be mono")
        if w.getsampwidth() != 2:
            raise SystemExit("wav must be 16-bit PCM")
        sr = w.getframerate()
        frames = w.readframes(w.getnframes())

    p = subprocess.Popen(
        [sys.executable, SERVICE],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        text=True,
    )
    if p.stdin is None or p.stdout is None:
        raise RuntimeError("Failed to open subprocess pipes")

    sid = str(uuid.uuid4())
    start_params = {"session_id": sid, "sample_rate_hz": str(sr)}
    if mixed:
        start_params["mixed"] = "true"
    if language is not None:
        start_params["language"] = str(language)
    p.stdin.write(json.dumps(req("stream_start", start_params)) + "\n")
    p.stdin.flush()
    _ = p.stdout.readline()

    # Push in ~300ms chunks.
    chunk_bytes = int(sr * 0.3) * 2
    for i in range(0, len(frames), chunk_bytes):
        chunk = frames[i : i + chunk_bytes]
        b64 = base64.b64encode(chunk).decode("ascii")
        p.stdin.write(
            json.dumps(
                req(
                    "stream_push",
                    {"session_id": sid, "format": "pcm_s16le_b64", "audio_b64": b64},
                )
            )
            + "\n"
        )
        p.stdin.flush()
        resp_line = p.stdout.readline().strip()
        if resp_line:
            try:
                resp = json.loads(resp_line)
                result = resp.get("result") or {}
                kind = result.get("kind")
                text = result.get("text")
                actions = result.get("actions")
                if kind in ("partial", "final") and text:
                    sys.stderr.write(f"[{kind}] {text}\n")
                if actions:
                    sys.stderr.write(f"[{kind}:actions] {actions}\n")
            except Exception:
                pass

    p.stdin.write(json.dumps(req("stream_finalize", {"session_id": sid})) + "\n")
    p.stdin.flush()
    line = p.stdout.readline().strip()
    if not line:
        p.terminate()
        raise RuntimeError("No response from service")
    p.terminate()
    resp = json.loads(line)
    actions = (resp.get("result") or {}).get("actions")
    if actions:
        sys.stderr.write(f"[actions] {actions}\n")
    return resp


def main():
    if len(sys.argv) < 2:
        raise SystemExit(
            "Usage: jsp_test_client.py [--mixed] [--language zh|auto|en] ping|capabilities|stream_wav <wav>"
        )

    mixed, language, idx = parse_flags(sys.argv)
    if idx >= len(sys.argv):
        raise SystemExit("Missing command")

    cmd = sys.argv[idx]
    if cmd == "ping":
        print(json.dumps(run_one(req("ping")), indent=2, ensure_ascii=True))
        return
    if cmd == "capabilities":
        print(json.dumps(run_one(req("capabilities")), indent=2, ensure_ascii=True))
        return
    if cmd == "stream_wav":
        if idx + 1 >= len(sys.argv):
            raise SystemExit("stream_wav needs a path")
        print(
            json.dumps(
                stream_wav(sys.argv[idx + 1], mixed=mixed, language=language),
                indent=2,
                ensure_ascii=True,
            )
        )
        return

    raise SystemExit("Unknown command")


if __name__ == "__main__":
    main()

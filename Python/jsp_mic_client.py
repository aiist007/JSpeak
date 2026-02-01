#!/usr/bin/env python3

"""Live microphone client for JSpeak speech service.

Requirements (recommended):
  - python3 -m pip install -r JSpeak/Python/requirements.txt
  - python3 -m pip install sounddevice
  - If sounddevice fails to install/run, you may need: brew install portaudio

Examples:
  python3 JSpeak/Python/jsp_mic_client.py --mixed
  python3 JSpeak/Python/jsp_mic_client.py --language zh

Controls:
  - Ctrl-C to stop and finalize
"""

import base64
import json
import os
import queue
import subprocess
import sys
import threading
import time
import uuid


def _service_path() -> str:
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(here, "jsp_speech_service.py")


def _req(method: str, params: dict | None = None) -> dict:
    return {"id": str(uuid.uuid4()), "method": method, "params": params or {}}


class LinearResampler:
    def __init__(self, in_sr: int, out_sr: int):
        self.in_sr = int(in_sr)
        self.out_sr = int(out_sr)
        self.step = float(self.in_sr) / float(self.out_sr)
        self.in_index = 0
        self.next_pos = 0.0

    def process(self, x_f32):
        import numpy as np

        x = x_f32
        if x.ndim != 1:
            x = x.reshape((-1,))
        n = int(x.size)
        if n < 2:
            self.in_index += n
            return np.zeros((0,), dtype=np.float32)

        chunk_start = self.in_index
        chunk_end = self.in_index + n

        # Generate positions that can be interpolated within this chunk.
        last_pos = chunk_end - 1
        if self.next_pos > last_pos:
            self.in_index += n
            return np.zeros((0,), dtype=np.float32)

        positions = np.arange(self.next_pos, last_pos, self.step, dtype=np.float64)
        if positions.size == 0:
            self.in_index += n
            return np.zeros((0,), dtype=np.float32)

        rel = positions - float(chunk_start)
        i0 = np.floor(rel).astype(np.int64)
        frac = (rel - i0).astype(np.float32)
        # Safety: ensure i0+1 in range
        i0 = np.clip(i0, 0, n - 2)
        y = (x[i0] * (1.0 - frac)) + (x[i0 + 1] * frac)

        self.next_pos = float(positions[-1] + self.step)
        self.in_index += n
        return y.astype(np.float32, copy=False)


def _parse_args(argv):
    mixed = False
    language = None
    partial_interval_ms = 500
    model = None
    device = None
    i = 1
    while i < len(argv):
        a = argv[i]
        if a == "--mixed":
            mixed = True
            i += 1
            continue
        if a == "--language" and i + 1 < len(argv):
            language = argv[i + 1]
            i += 2
            continue
        if a == "--partial-interval-ms" and i + 1 < len(argv):
            partial_interval_ms = int(argv[i + 1])
            i += 2
            continue
        if a == "--model" and i + 1 < len(argv):
            model = argv[i + 1]
            i += 2
            continue
        if a == "--device" and i + 1 < len(argv):
            device = argv[i + 1]
            i += 2
            continue
        if a in ("-h", "--help"):
            return None
        raise SystemExit(f"Unknown arg: {a}")

    return {
        "mixed": mixed,
        "language": language,
        "partial_interval_ms": partial_interval_ms,
        "model": model,
        "device": device,
    }


def main() -> int:
    args = _parse_args(sys.argv)
    if args is None:
        print(
            "Usage: jsp_mic_client.py [--mixed] [--language zh|auto|en] [--partial-interval-ms 500] [--model <hf_repo>] [--device <name_or_index>]",
            file=sys.stderr,
        )
        return 2

    try:
        import numpy as np
    except Exception as e:
        raise SystemExit(f"numpy not available: {e}")

    try:
        import sounddevice as sd
    except Exception as e:
        print(
            "sounddevice not available. Install: python3 -m pip install sounddevice (and maybe: brew install portaudio)",
            file=sys.stderr,
        )
        raise SystemExit(str(e))

    service = subprocess.Popen(
        [sys.executable, _service_path()],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        text=True,
        bufsize=1,
    )
    if service.stdin is None or service.stdout is None:
        raise RuntimeError("Failed to open service pipes")

    session_id = str(uuid.uuid4())
    out_sr = 16000

    q: "queue.Queue[np.ndarray]" = queue.Queue(maxsize=50)
    stop = threading.Event()

    def audio_cb(indata, frames, time_info, status):
        if stop.is_set():
            return
        x = indata[:, 0].astype(np.float32, copy=True)
        try:
            q.put_nowait(x)
        except queue.Full:
            # Drop if we can't keep up.
            pass

    # Choose input sample rate: try device default; resample to 16k.
    dev_info = None
    try:
        dev_info = sd.query_devices(args["device"], "input")
    except Exception:
        dev_info = sd.query_devices(None, "input")
    in_sr = int(dev_info.get("default_samplerate") or 48000)
    resampler = LinearResampler(in_sr=in_sr, out_sr=out_sr)

    start_params = {
        "session_id": session_id,
        "sample_rate_hz": str(out_sr),
        "partial_interval_ms": str(args["partial_interval_ms"]),
    }
    if args["mixed"]:
        start_params["mixed"] = "true"
    if args["language"] is not None:
        start_params["language"] = str(args["language"])
    if args["model"] is not None:
        start_params["model"] = str(args["model"])

    service.stdin.write(json.dumps(_req("stream_start", start_params)) + "\n")
    service.stdin.flush()
    _ = service.stdout.readline()

    print(
        f"JSpeak mic streaming started (device_sr={in_sr} -> 16000). Ctrl-C to stop.",
        file=sys.stderr,
    )

    chunk_bytes_target = int(0.30 * out_sr) * 2
    out_pcm_buf = bytearray()

    try:
        with sd.InputStream(
            device=args["device"],
            channels=1,
            samplerate=in_sr,
            dtype="float32",
            callback=audio_cb,
            blocksize=0,
        ):
            while True:
                try:
                    x = q.get(timeout=0.25)
                except queue.Empty:
                    continue

                y = resampler.process(x)
                if y.size == 0:
                    continue
                pcm16 = np.clip(y * 32768.0, -32768, 32767).astype(np.int16).tobytes()
                out_pcm_buf.extend(pcm16)

                while len(out_pcm_buf) >= chunk_bytes_target:
                    chunk = bytes(out_pcm_buf[:chunk_bytes_target])
                    del out_pcm_buf[:chunk_bytes_target]
                    b64 = base64.b64encode(chunk).decode("ascii")
                    service.stdin.write(
                        json.dumps(
                            _req(
                                "stream_push",
                                {
                                    "session_id": session_id,
                                    "format": "pcm_s16le_b64",
                                    "audio_b64": b64,
                                },
                            )
                        )
                        + "\n"
                    )
                    service.stdin.flush()

                    line = service.stdout.readline().strip()
                    if not line:
                        continue
                    resp = json.loads(line)
                    result = resp.get("result") or {}
                    kind = result.get("kind")
                    text = result.get("text")
                    actions = result.get("actions")
                    if kind in ("partial", "final") and text:
                        sys.stderr.write(f"[{kind}] {text}\n")
                    if actions:
                        sys.stderr.write(f"[{kind}:actions] {actions}\n")

    except KeyboardInterrupt:
        pass
    finally:
        stop.set()

    # Finalize any remaining audio.
    if out_pcm_buf:
        b64 = base64.b64encode(bytes(out_pcm_buf)).decode("ascii")
        service.stdin.write(
            json.dumps(
                _req(
                    "stream_push",
                    {
                        "session_id": session_id,
                        "format": "pcm_s16le_b64",
                        "audio_b64": b64,
                    },
                )
            )
            + "\n"
        )
        service.stdin.flush()
        _ = service.stdout.readline()

    service.stdin.write(
        json.dumps(_req("stream_finalize", {"session_id": session_id})) + "\n"
    )
    service.stdin.flush()
    final_line = service.stdout.readline().strip()
    if final_line:
        final = json.loads(final_line)
        actions = (final.get("result") or {}).get("actions")
        if actions:
            sys.stderr.write(f"[final:actions] {actions}\n")

    service.terminate()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

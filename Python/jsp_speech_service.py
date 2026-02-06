#!/usr/bin/env python3

"""JSpeak local speech service (JSONL over stdin/stdout).

Protocol (each request/response is one JSON line):

Request:
  {"id": "...", "method": "...", "params": {"k": "v", ...}}

Response:
  {"id": "...", "ok": true|false, "result": {...}|null, "error": "..."|null}

Implemented methods:
  - ping
  - capabilities
  - stream_start
  - stream_push
  - stream_finalize

Language:
  - default: zh (prefer Chinese)
  - mixed mode: set params.mixed = "true" to enable auto language detection (recommended for ZH+EN)

Partial output:
  - stream_start params.partial_interval_ms (default: 500)
  - stream_push response.result.kind = partial|final|none

Commands:
  - If a final transcript exactly matches a command phrase, service returns structured actions.
  - For non-command utterances, service returns actions: [{"type":"insert","text":"..."}]
  - For partial results, service returns actions: [{"type":"set_composition","text":"..."}]

Audio encoding for stream_push:
  - params.format = "pcm_s16le_b64"
  - params.sample_rate_hz = "16000" (recommended)
  - params.audio_b64 = base64 of raw little-endian int16 PCM mono
"""

import base64
import json
import os
import re
import sys
import time
import uuid
from dataclasses import dataclass, field
from typing import Any, Dict, Optional, Tuple


def _now() -> float:
    return time.time()


def _write(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=True) + "\n")
    sys.stdout.flush()


def _ok(req_id: str, result: Optional[dict] = None):
    return {"id": req_id, "ok": True, "result": result or {}, "error": None}


def _err(req_id: str, message: str):
    return {"id": req_id, "ok": False, "result": None, "error": message}


def _get_str(params: dict, key: str, default: Optional[str] = None) -> Optional[str]:
    v = params.get(key)
    if v is None:
        return default
    if isinstance(v, str):
        return v
    return str(v)


def _get_bool(params: dict, key: str, default: bool = False) -> bool:
    v = params.get(key)
    if v is None:
        return default
    if isinstance(v, bool):
        return v
    if isinstance(v, (int, float)):
        return bool(v)
    if isinstance(v, str):
        return v.strip().lower() in ("1", "true", "yes", "y", "on")
    return default


def _normalize_language(language: Optional[str], mixed: bool) -> Optional[str]:
    # Prefer Chinese by default, but allow mixed EN+ZH.
    # In Whisper, setting language to None enables auto language detection.
    if mixed:
        return None
    if not language:
        return "zh"
    l = language.strip().lower()
    if l in ("auto", "detect", ""):
        return None
    if l in ("zh", "zh-cn", "zh-hans", "cn"):
        return "zh"
    if l in ("en", "en-us", "english"):
        return "en"
    return language


def _default_prompt_for(language: Optional[str]) -> Optional[str]:
    # Non-ASCII here is intentional: it improves Chinese punctuation/formatting.
    if language == "en":
        return "Transcribe accurately. Keep punctuation and casing."
    return (
        "请优先使用简体中文标点与表达，保留英文单词/缩写原样，必要时中英文之间加空格。"
    )


_RE_CJK_ASCII = re.compile(r"([\u4e00-\u9fff])([A-Za-z0-9])")
_RE_ASCII_CJK = re.compile(r"([A-Za-z0-9])([\u4e00-\u9fff])")


def _normalize_mixed_spacing(text: str) -> str:
    # Light post-process to improve ZH+EN readability.
    text = _RE_CJK_ASCII.sub(r"\1 \2", text)
    text = _RE_ASCII_CJK.sub(r"\1 \2", text)
    return text


_RE_END_PUNCT = re.compile(r"[\.!\?\u3002\uff01\uff1f\u2026]+$")
_RE_TRAILING_PUNCT = re.compile(r"[\.!\?\u3002\uff01\uff1f\u2026]+$")
_RE_CN_COMMA = re.compile(r"[\uff0c,]")
_RE_CN_CONNECTOR = re.compile(
    r"(但是|不过|然后|所以|因此|而且|并且|同时|另外|因为|如果|虽然|接着|随后)"
)


def _looks_like_question(text: str) -> bool:
    t = text.strip()
    if not t:
        return False
    t = _RE_TRAILING_PUNCT.sub("", t).strip()
    if not t:
        return False

    lower = t.lower()

    # Strong Chinese question cues.
    if re.search(r"(吗|么)\s*$", t):
        return True
    if re.search(r"(是不是|是否|能不能|可不可以|可以吗|要不要|需不需要|有没有)", t):
        return True
    if re.match(
        r"^(怎么|为什么|为啥|多少|几|哪(里|儿|个|些|种|位)?|谁|啥|什么|何时|什么时候)",
        t,
    ):
        return True

    # English question cues.
    if re.match(
        r"^(can|could|would|should|do|does|did|is|are|am|was|were|what|why|how|when|where|which|who)\b",
        lower,
    ):
        return True

    return False


def _maybe_insert_cn_comma(text: str) -> str:
    if not text:
        return text
    if not re.search(r"[\u4e00-\u9fff]", text):
        return text
    if _RE_CN_COMMA.search(text):
        return text
    if len(text) < 14:
        return text
    m = _RE_CN_CONNECTOR.search(text)
    if not m:
        return text
    idx = m.start()
    if idx <= 1:
        return text
    return text[:idx] + "，" + text[idx:]


def _apply_tone_punctuation(text: str) -> str:
    t = text.strip()
    if not t:
        return t
    has_cjk = bool(re.search(r"[\u4e00-\u9fff]", t))
    base = _RE_TRAILING_PUNCT.sub("", t).strip()
    if not base:
        return t
    base = _maybe_insert_cn_comma(base)
    if _looks_like_question(base):
        return base + ("？" if has_cjk else "?")
    if _RE_END_PUNCT.search(t):
        if has_cjk and t.endswith("."):
            return base + "。"
        return t
    return base + ("。" if has_cjk else ".")


def _clean_command_text(text: str) -> str:
    return text.strip().strip("\r\n\t ,.!?;:，。！？；：")


def _command_key(text: str) -> str:
    # Normalize to match spoken config phrases.
    # Remove spaces and punctuation so minor ASR differences don't inject text.
    t = _clean_command_text(text).lower()
    t = re.sub(r"[\s,\.\!\?;:\uff0c\u3002\uff01\uff1f\uff1b\uff1a]", "", t)
    return t


_SUPPRESSED_KEYS = {
    _command_key("请优先使用简体中文标点与表达，保留英文单词"),
    _command_key("请使用简体中文标点与表达，保留英文单词"),
    _command_key("请优先使用简体中文标点与表达，保留英文单词/缩写原样"),
}


def _is_suppressed_phrase(text: str) -> bool:
    return _command_key(text) in _SUPPRESSED_KEYS


def _command_actions(text: str) -> Optional[list]:
    t = _clean_command_text(text).lower()
    if not t:
        return None

    # Spoken prompt/config phrases: do not insert as text.
    # (We already apply this behavior via initial_prompt by default.)
    if _is_suppressed_phrase(t):
        return []

    if t in ("换行", "回车", "下一行", "new line", "newline", "enter"):
        return [{"type": "insert", "text": "\n"}]

    if t in ("空格", "space"):
        return [{"type": "insert", "text": " "}]

    if t in ("删除", "退格", "backspace", "delete"):
        return [{"type": "delete_backward", "count": 1}]

    if t in ("删除一个词", "删除上一个词", "delete word", "delete last word"):
        return [{"type": "delete_backward_word", "count": 1}]

    if t in ("删除一句", "删除上一句", "delete sentence", "delete last sentence"):
        return [{"type": "delete_backward_sentence", "count": 1}]

    if t in ("撤销", "undo"):
        return [{"type": "system_undo"}]

    if t in ("重做", "redo"):
        return [{"type": "system_redo"}]

    if t in ("清空", "清除", "clear"):
        return [{"type": "clear"}]

    punct_map = {
        "逗号": "，",
        "句号": "。",
        "问号": "？",
        "感叹号": "！",
        "冒号": "：",
        "分号": "；",
        "comma": ",",
        "period": ".",
        "question mark": "?",
        "exclamation mark": "!",
        "colon": ":",
        "semicolon": ";",
    }
    if t in punct_map:
        return [{"type": "insert", "text": punct_map[t]}]

    return None


def _compose_actions(kind: str, text: str, actions: list) -> list:
    # Two-stage client model:
    # - partial -> set_composition
    # - final -> commit (actions already suitable for commit)
    if kind == "partial":
        return [{"type": "set_composition", "text": text}]
    return actions


def _decode_pcm_s16le_b64(audio_b64: str) -> "bytes":
    return base64.b64decode(audio_b64.encode("ascii"), validate=True)


def _pcm16_bytes_to_float32_mono(pcm16: bytes):
    # Lazy import to keep startup fast when only ping/capabilities is used.
    import numpy as np

    arr = np.frombuffer(pcm16, dtype=np.int16)
    if arr.size == 0:
        return np.zeros((0,), dtype=np.float32)
    # int16 -> [-1, 1)
    return (arr.astype(np.float32) / 32768.0).copy()


class EnergyVAD:
    """Very small VAD for endpointing.

    This is a fallback that requires no extra deps.
    Tune thresholds later; this is good enough to get streaming working.
    """

    def __init__(
        self, sample_rate_hz: int, frame_ms: int = 30, rms_threshold: float = 0.012
    ):
        self.sample_rate_hz = sample_rate_hz
        self.frame_ms = frame_ms
        self.rms_threshold = rms_threshold

    def is_speech(self, frame_f32) -> bool:
        import numpy as np

        if frame_f32.size == 0:
            return False
        rms = float(np.sqrt(np.mean(frame_f32 * frame_f32)))
        return rms >= self.rms_threshold


@dataclass
class StreamSession:
    sample_rate_hz: int
    language: Optional[str] = None
    prompt: Optional[str] = None
    created_at: float = field(default_factory=_now)
    # Audio accumulation
    buffer_f32: Any = None
    # Endpointing
    vad: EnergyVAD = None  # type: ignore[assignment]
    speech_frames: int = 0
    silence_frames: int = 0
    last_emitted_text: str = ""
    segments_text: str = ""
    # Partial output
    partial_interval_ms: int = 500
    max_partial_context_s: int = 20
    min_partial_speech_ms: int = 300
    last_partial_samples: int = 0
    committed_prefix: str = ""
    last_prefix_candidate: str = ""
    prefix_streak: int = 0
    # Config
    frame_ms: int = 30
    end_silence_ms: int = 450

    def __post_init__(self):
        import numpy as np

        self.buffer_f32 = np.zeros((0,), dtype=np.float32)
        self.vad = EnergyVAD(self.sample_rate_hz, frame_ms=self.frame_ms)

    def reset_current_utterance(self):
        import numpy as np

        self.buffer_f32 = np.zeros((0,), dtype=np.float32)
        self.speech_frames = 0
        self.silence_frames = 0
        self.last_emitted_text = ""
        self.last_partial_samples = 0
        self.committed_prefix = ""
        self.last_prefix_candidate = ""
        self.prefix_streak = 0

    def push_audio(self, audio_f32) -> Tuple[bool, int, int]:
        import numpy as np

        if audio_f32.size == 0:
            return False, self.speech_frames, self.silence_frames

        self.buffer_f32 = np.concatenate((self.buffer_f32, audio_f32))

        frame_len = int(self.sample_rate_hz * (self.frame_ms / 1000.0))
        if frame_len <= 0:
            return False, self.speech_frames, self.silence_frames

        # Analyze only the newest whole frames.
        n_frames = int(audio_f32.size // frame_len)
        if n_frames <= 0:
            return False, self.speech_frames, self.silence_frames

        # Take the tail portion that aligns with frames.
        start = audio_f32.size - (n_frames * frame_len)
        frames = audio_f32[start:].reshape((n_frames, frame_len))

        endpoint = False
        for i in range(n_frames):
            if self.vad.is_speech(frames[i]):
                self.speech_frames += 1
                self.silence_frames = 0
            else:
                self.silence_frames += 1
                # End-of-utterance when we've seen some speech and enough silence.
                if (
                    self.speech_frames > 0
                    and (self.silence_frames * self.frame_ms) >= self.end_silence_ms
                ):
                    endpoint = True

        return endpoint, self.speech_frames, self.silence_frames


def _common_prefix_len(a: str, b: str) -> int:
    n = min(len(a), len(b))
    i = 0
    while i < n and a[i] == b[i]:
        i += 1
    return i


def _boundary_prefix(text: str) -> str:
    # Return a prefix that ends at a natural boundary (space / newline / punctuation).
    if not text:
        return ""

    boundary_chars = set(
        [
            " ",
            "\t",
            "\n",
            "\r",
            ",",
            ".",
            "!",
            "?",
            ";",
            ":",
            "，",
            "。",
            "！",
            "？",
            "；",
            "：",
        ]
    )

    i = len(text) - 1
    while i >= 0:
        ch = text[i]
        if ch in boundary_chars:
            return text[: i + 1]
        i -= 1
    return ""


class WhisperEngine:
    def __init__(self):
        self._model = None
        self._model_name = None

    def ensure_loaded(self, model: str):
        if self._model is not None and self._model_name == model:
            return
        try:
            import mlx_whisper  # type: ignore[import-not-found]  # noqa: F401
        except Exception as e:
            raise RuntimeError(
                "mlx-whisper is not installed. Run: pip install -r JSpeak/Python/requirements.txt"
            ) from e

        # mlx-whisper loads model lazily by repo id or path.
        self._model = model
        self._model_name = model

    def is_loaded(self, model: str) -> bool:
        return self._model is not None and self._model_name == model

    def transcribe(
        self,
        audio_f32,
        sample_rate_hz: int,
        language: Optional[str],
        prompt: Optional[str],
    ) -> str:
        try:
            import mlx_whisper  # type: ignore[import-not-found]
        except Exception as e:
            raise RuntimeError(
                "mlx-whisper is not installed. Run: pip install -r JSpeak/Python/requirements.txt"
            ) from e

        # mlx_whisper expects audio as numpy array, sample rate is inferred for raw arrays as 16k.
        # We resample later if needed; for now we require 16k for simplicity.
        if sample_rate_hz != 16000:
            raise ValueError(
                "Only 16000Hz supported right now (got %d)" % sample_rate_hz
            )

        kwargs = {}
        if language:
            kwargs["language"] = language
        if prompt:
            kwargs["initial_prompt"] = prompt

        model = self._model_name
        if not model:
            raise RuntimeError("Model is not loaded. Call stream_start first.")

        result = mlx_whisper.transcribe(audio_f32, path_or_hf_repo=model, **kwargs)
        raw = result.get("text") or ""
        if not isinstance(raw, str):
            raw = str(raw)
        text = raw.strip()
        return text


class Service:
    def __init__(self):
        self.engine = WhisperEngine()
        self.sessions: Dict[str, StreamSession] = {}

    def handle(self, req: dict) -> dict:
        req_id = req.get("id") or str(uuid.uuid4())
        method = req.get("method")
        params = req.get("params") or {}
        if not isinstance(params, dict):
            params = {}

        try:
            if method == "ping":
                return _ok(
                    req_id,
                    {"message": "jspeak-speech-service alive", "time": str(_now())},
                )

            if method == "capabilities":
                return _ok(
                    req_id,
                    {
                        "protocol": "jsonl-1",
                        "streaming": "true",
                        "audio_formats": "pcm_s16le_b64",
                        "sample_rates_hz": "16000",
                        "asr": "mlx-whisper",
                        "recommended_model": "mlx-community/whisper-medium",
                        "supports_local_model_path": "true",
                        "default_language": "zh",
                        "language_modes": "zh,auto,en",
                        "mixed_mode": "true",
                    },
                )

            if method == "stream_start":
                session_id = _get_str(params, "session_id") or str(uuid.uuid4())
                sample_rate_hz = int(
                    _get_str(params, "sample_rate_hz", "16000") or "16000"
                )
                mixed = _get_bool(params, "mixed", default=False)
                language = _normalize_language(
                    _get_str(params, "language"), mixed=mixed
                )
                prompt = _get_str(params, "prompt") or _default_prompt_for(language)
                model_path = _get_str(params, "model_path") or os.environ.get(
                    "JSPEAK_MODEL_PATH"
                )
                model = model_path or _get_str(
                    params, "model", "mlx-community/whisper-medium"
                )
                if not model:
                    return _err(req_id, "Missing model")
                try:
                    if not self.engine.is_loaded(model):
                        sys.stderr.write(f"Loading model {model}...\n")
                        sys.stderr.flush()
                        self.engine.ensure_loaded(model)
                        sys.stderr.write("Model loaded.\n")
                        sys.stderr.flush()
                except Exception as e:
                    import traceback

                    traceback.print_exc(file=sys.stderr)
                    sys.stderr.flush()
                    return _err(req_id, f"Model load failed: {e}")

                partial_interval_ms = int(
                    _get_str(params, "partial_interval_ms", "500") or "500"
                )
                max_partial_context_s = int(
                    _get_str(params, "max_partial_context_s", "20") or "20"
                )
                min_partial_speech_ms = int(
                    _get_str(params, "min_partial_speech_ms", "300") or "300"
                )
                end_silence_ms = int(_get_str(params, "end_silence_ms", "450") or "450")
                sess = StreamSession(
                    sample_rate_hz=sample_rate_hz,
                    language=language,
                    prompt=prompt,
                    partial_interval_ms=partial_interval_ms,
                    max_partial_context_s=max_partial_context_s,
                    min_partial_speech_ms=min_partial_speech_ms,
                    end_silence_ms=end_silence_ms,
                )
                self.sessions[session_id] = sess
                return _ok(req_id, {"session_id": session_id, "model": model})

            if method == "stream_push":
                session_id = _get_str(params, "session_id")
                if not session_id or session_id not in self.sessions:
                    return _err(req_id, "Unknown session_id")
                fmt = _get_str(params, "format", "")
                if fmt != "pcm_s16le_b64":
                    return _err(req_id, "Unsupported format (expected pcm_s16le_b64)")
                audio_b64 = _get_str(params, "audio_b64")
                if not audio_b64:
                    return _err(req_id, "Missing audio_b64")

                pcm16 = _decode_pcm_s16le_b64(audio_b64)
                audio_f32 = _pcm16_bytes_to_float32_mono(pcm16)
                sess: StreamSession = self.sessions[session_id]
                endpoint, speech_frames, silence_frames = sess.push_audio(audio_f32)

                emitted_text = ""
                emitted_final = "false"
                emitted_kind = "none"
                committed_text = ""
                stable_prefix = ""
                unstable_suffix = ""
                delta_from = "0"
                delta_delete = "0"
                delta_insert = ""
                actions = []

                # Partial: transcribe periodically while speech is ongoing.
                if not endpoint and speech_frames > 0:
                    if (speech_frames * sess.frame_ms) < sess.min_partial_speech_ms:
                        sess.last_partial_samples = int(sess.buffer_f32.size)
                        return _ok(
                            req_id,
                            {
                                "session_id": session_id,
                                "endpoint": "false",
                                "speech_frames": str(speech_frames),
                                "silence_frames": str(silence_frames),
                                "text": "",
                                "final": "false",
                                "kind": "none",
                                "committed_text": "",
                                "actions": [],
                                "stable_prefix": "",
                                "unstable_suffix": "",
                                "delta_from": "0",
                                "delta_delete": "0",
                                "delta_insert": "",
                            },
                        )
                    interval_samples = int(
                        sess.sample_rate_hz * (sess.partial_interval_ms / 1000.0)
                    )
                    if (
                        interval_samples > 0
                        and (sess.buffer_f32.size - sess.last_partial_samples)
                        >= interval_samples
                    ):
                        start = max(
                            0,
                            int(
                                sess.buffer_f32.size
                                - (sess.max_partial_context_s * sess.sample_rate_hz)
                            ),
                        )
                        window = sess.buffer_f32[start:]
                        text = self.engine.transcribe(
                            window, sess.sample_rate_hz, sess.language, sess.prompt
                        )
                        if text:
                            # Stabilize prefix to reduce jitter.
                            candidate = _boundary_prefix(text)
                            if candidate and candidate == sess.last_prefix_candidate:
                                sess.prefix_streak += 1
                            else:
                                sess.last_prefix_candidate = candidate
                                sess.prefix_streak = 1 if candidate else 0

                            if candidate and sess.prefix_streak >= 2:
                                # Monotonic growth only.
                                if len(candidate) > len(
                                    sess.committed_prefix
                                ) and candidate.startswith(sess.committed_prefix):
                                    sess.committed_prefix = candidate

                            stable_prefix = sess.committed_prefix
                            unstable_suffix = text[len(stable_prefix) :]
                            full_text = stable_prefix + unstable_suffix

                            prev = sess.last_emitted_text
                            cpl = _common_prefix_len(prev, full_text)
                            delta_from = str(cpl)
                            delta_delete = str(len(prev) - cpl)
                            delta_insert = full_text[cpl:]

                            if full_text != prev:
                                emitted_text = full_text
                                sess.last_emitted_text = full_text
                                emitted_kind = "partial"
                        sess.last_partial_samples = int(sess.buffer_f32.size)

                # Final: on endpoint, transcribe full utterance and reset.
                if endpoint:
                    text = self.engine.transcribe(
                        sess.buffer_f32, sess.sample_rate_hz, sess.language, sess.prompt
                    )
                    text = _normalize_mixed_spacing(text)
                    is_command = False
                    actions = _command_actions(text)
                    if actions is not None:
                        is_command = True
                    else:
                        text = _apply_tone_punctuation(text)
                        actions = [{"type": "insert", "text": text}] if text else []
                    stable_prefix = ""
                    unstable_suffix = ""
                    emitted_text = text
                    committed_text = "" if is_command else text
                    prev = sess.last_emitted_text
                    cpl = _common_prefix_len(prev, text)
                    delta_from = str(cpl)
                    delta_delete = str(len(prev) - cpl)
                    delta_insert = text[cpl:]
                    emitted_final = "true"
                    emitted_kind = "final"
                    if text:
                        sess.segments_text = text
                    sess.reset_current_utterance()

                # Normalize actions for a 2-stage IME (composition -> commit)
                if emitted_kind == "partial":
                    actions = _compose_actions("partial", emitted_text, actions)
                elif emitted_kind == "final":
                    actions = _compose_actions("final", emitted_text, actions)

                return _ok(
                    req_id,
                    {
                        "session_id": session_id,
                        "endpoint": "true" if endpoint else "false",
                        "speech_frames": str(speech_frames),
                        "silence_frames": str(silence_frames),
                        "text": emitted_text,
                        "final": emitted_final,
                        "kind": emitted_kind,
                        "committed_text": committed_text,
                        "actions": actions,
                        "stable_prefix": stable_prefix,
                        "unstable_suffix": unstable_suffix,
                        "delta_from": delta_from,
                        "delta_delete": delta_delete,
                        "delta_insert": delta_insert,
                    },
                )

            if method == "stream_finalize":
                session_id = _get_str(params, "session_id")
                if not session_id or session_id not in self.sessions:
                    return _err(req_id, "Unknown session_id")
                sess = self.sessions.pop(session_id)
                # If stream_push already reached an endpoint, it may have reset the
                # current utterance buffer. In that case, reuse the last finalized text.
                text = ""
                try:
                    if getattr(sess.buffer_f32, "size", 0) > 0:
                        text = self.engine.transcribe(
                            sess.buffer_f32,
                            sess.sample_rate_hz,
                            sess.language,
                            sess.prompt,
                        )
                    elif getattr(sess, "segments_text", ""):
                        text = sess.segments_text
                except Exception:
                    # Fall through to error handling below.
                    raise
                text = _normalize_mixed_spacing(text)
                actions = _command_actions(text)
                if actions is None:
                    text = _apply_tone_punctuation(text)
                    actions = [{"type": "insert", "text": text}] if text else []
                return _ok(
                    req_id, {"session_id": session_id, "text": text, "actions": actions}
                )

            return _err(req_id, f"Unknown method: {method}")
        except Exception as e:
            return _err(req_id, str(e))


def main():
    svc = Service()
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
            resp = svc.handle(req)
        except Exception as e:
            resp = _err("", f"Bad request: {e}")
        _write(resp)


if __name__ == "__main__":
    main()

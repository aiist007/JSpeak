# JSpeak Functional Specification (Current)

Last updated: 2026-01-31

JSpeak is a local-first voice typing agent for macOS. It captures microphone audio, transcribes speech locally (Whisper via MLX), optionally recognizes simple voice commands, and injects text into the currently focused application.

This document describes what JSpeak can do today, how it behaves, required permissions, and the technologies/frameworks used.

## 1. Product Modes

### 1.1 Non-IME Mode (Primary)

JSpeak runs as a background menubar agent (no input method registration required).

- Trigger: global Fn (hold-to-talk) and F6 fallback (toggle)
- Output: injects text into the active application
- Injection strategy: Accessibility first, then paste fallback

### 1.2 IME Mode (Experimental / Not Primary)

There is a scaffold for an InputMethodKit-based IME host. On current macOS builds, registration into the system input method list may be inconsistent without additional packaging/signing steps.

## 2. Core User Flow (Non-IME)

### 2.1 Start/Stop Recording

- Start: hold Fn (or press F6)
- Stop: release Fn (or press F6 again)

### 2.2 Audio Capture

- Captures microphone input using AVAudioEngine
- Converts audio to 16kHz mono PCM s16le in real time
- On stop, the captured PCM is sent for transcription

### 2.3 Transcription

- Local transcription service runs as a Python subprocess
- Model: default currently uses `mlx-community/whisper-medium`
- Languages:
  - Chinese-first by default
  - Mixed Chinese+English supported (auto language detection)

### 2.4 Text Injection

When transcription returns `actions`, JSpeak applies them:

- Primary: Accessibility API (AX) insertion
  - Uses `kAXSelectedTextAttribute` and verifies insertion by reading back selected text
- Fallback: paste injection
  - Places text onto clipboard temporarily and sends Cmd+V

Current supported action types (subset):

- `insert` (text)
- `delete_backward` (count)
- `clear`

## 3. Voice Commands (Service-Level)

The Python speech service can map certain final transcripts to structured actions.

Examples:

- "换行" -> insert "
"
- "删除" -> delete backward 1
- "清空" -> clear
- Common punctuation words (逗号/句号/问号/...) -> insert punctuation

Note: Command coverage is currently basic and intended as a foundation.

## 4. Performance Characteristics

### 4.1 First-Run Behavior

First run can be slower due to:

- Installing Python dependencies
- First-time model download from HuggingFace
- First-time model initialization

Subsequent transcriptions are faster once the environment and model are cached.

### 4.2 Latency Model

Current implementation is mostly "record a chunk, then transcribe" (not full streaming injection yet).

Planned optimization (next):

- Stream audio chunks to the Python service
- Use partial results for a live preview and finalize on endpoint/pause

## 5. Permissions Required (Non-IME)

JSpeakAgent requires these macOS permissions:

- Microphone: audio capture
- Accessibility: inject text via AX into other apps
- Input Monitoring: capture global Fn/F6

If Accessibility is not granted or target apps do not support AX insertion, JSpeak will fall back to paste injection.

## 6. Developer Interfaces / Protocols

### 6.1 Swift <-> Python IPC

Transport:

- Python subprocess spawned from Swift using `Process`
- IPC via stdin/stdout JSON Lines (JSONL)

High-level methods:

- `ping`
- `capabilities`
- `stream_start`
- `stream_push`
- `stream_finalize`

### 6.2 JSONL Response Shape (Concept)

Responses include:

- `ok`: boolean
- `result`: dict
- `result.actions`: list of dict actions (for final)

## 7. Technologies and Frameworks Used

### 7.1 Swift / macOS

- Swift Package Manager (SwiftPM): build and module structure
- AppKit: menubar agent (`NSStatusItem`), application lifecycle
- AVFoundation (AVFAudio): microphone capture and resampling via `AVAudioEngine` + `AVAudioConverter`
- ApplicationServices / Accessibility:
  - `AXUIElementCreateSystemWide`
  - `kAXFocusedUIElementAttribute`
  - `kAXSelectedTextAttribute`
- CoreGraphics:
  - `CGEvent` for paste fallback (Cmd+V) and basic key events
- InputMethodKit (scaffold): IME host skeleton

### 7.2 Python

- `mlx-whisper`: Whisper inference on Apple Silicon
- `mlx` / `mlx-metal`: compute backend
- `numpy`: audio conversion and numeric ops
- `huggingface_hub`: model download/cache

## 8. Current Limitations (Known)

- Streaming "live typing" (Typeless-style) is not fully implemented yet
  - Currently: record -> transcribe -> inject
- Fn detection may vary depending on system settings; F6 fallback exists
- Accessibility insertion may succeed but not apply in some apps; paste fallback is used
- Python packaging is not isolated yet (Homebrew Python + pip with `--break-system-packages`)
  - Plan: switch to a dedicated venv under app support

## 9. Roadmap Toward Typeless-Level UX (Planned)

- True streaming pipeline (push audio chunks, partial composition, final commit)
- Robust endpointing (better VAD, pause-based finalization)
- Floating caption near caret and clear recording state
- Configurable hotkeys and model selection (small/medium/turbo)
- Local semantic post-processing (fast punctuation/formatting) and optional advanced semantic mode


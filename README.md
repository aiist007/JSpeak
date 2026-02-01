# JSpeak

Local-first voice typing for macOS (Apple Silicon), built as a menubar app + local speech engine.

[![GitHub Release](https://img.shields.io/github/v/release/aiist007/JSpeak)](https://github.com/aiist007/JSpeak/releases)
[![Swift Version](https://img.shields.io/badge/Swift-6.0-orange)](https://swift.org)
[![Python](https://img.shields.io/badge/Python-3.14-blue)](https://python.org)

## Features

- 🎤 **Local Speech Recognition** - MLX-Whisper running entirely on your Mac (no cloud)
- ⌨️ **Global Hotkey** - Hold Fn or press F6 to dictate anywhere
- 🔒 **Privacy First** - No data leaves your machine
- 🇨🇳🇺🇸 **Bilingual Support** - Mixed Chinese/English transcription
- 📝 **Smart Punctuation** - Automatic question detection and punctuation
- ⚡ **Fast Warmup** - Model preloaded on launch

## Requirements

- macOS 13.0+ on Apple Silicon (M1/M2/M3)
- Python 3.14 (optional, bundled in releases)
- ~4GB RAM for Whisper Medium model

## Quick Start

### Download Release (Recommended)

1. Download `JSpeakBeta.zip` from [Releases](https://github.com/aiist007/JSpeak/releases)
2. Extract and move `JSpeakBeta.app` to `/Applications`
3. Grant permissions on first launch:
   - **Microphone**
   - **Accessibility** (for text injection)
   - **Input Monitoring** (for global hotkey)

### Build from Source

```bash
git clone https://github.com/aiist007/JSpeak.git
cd JSpeak

# Build release bundle
bash scripts/package_beta.sh

# Or run CLI for testing
swift run jspeak -- ping
```

## Usage

1. **Start JSpeak** - Click the JSpeak icon in your menubar
2. **Hold Fn** to record, **release Fn** to transcribe
3. **F6** works as a fallback hotkey
4. Dictate directly into any text field

### Commands

| Phrase | Action |
|--------|--------|
| 换行 / new line | Insert newline |
| 删除 / delete | Delete last word |
| 句号 / period | End sentence |

## Architecture

```
JSpeak/
├── Sources/JSpeakIMEHost/         # Swift menubar app (AppKit)
├── Sources/JSpeakPythonBridge/    # Swift-Python IPC bridge
├── Sources/JSpeakCLI/             # CLI tool for testing
├── Python/
│   └── jsp_speech_service.py      # MLX-Whisper speech engine
├── Assets/
│   ├── Models/whisper-medium/     # Bundled Whisper model
│   └── PythonRuntime/             # Embedded Python 3.14
└── scripts/
    └── package_beta.sh            # App bundling script
```

## Development

### Python Service (Test Independently)

```bash
# Test with mic
python3 Python/jsp_mic_client.py --mixed

# CLI ping
python3 Python/jsp_test_client.py ping
```

### Swift Development

```bash
# Debug build
swift build

# Run CLI
swift run jspeak -- ping

# Build release bundle
swift build -c release
```

## Permissions

JSpeak requires these macOS permissions:

| Permission | Purpose |
|------------|---------|
| Microphone | Record audio for transcription |
| Accessibility | Inject recognized text into apps |
| Input Monitoring | Detect global Fn/F6 hotkey |

## Troubleshooting

**Transcription fails on first run?**
- Wait for Python environment setup (may take a minute)
- Check Python is installed or use bundled version

**Text not appearing?**
- Ensure Accessibility permission is granted
- Try clicking the target text field first

**Fn key not working?**
- Check System Settings → Keyboard → Keyboard Shortcuts → Function Keys
- Use F6 as fallback

## License

MIT License - See [LICENSE](LICENSE) for details.

## Acknowledgments

- [MLX-Whisper](https://github.com/mlx-community/whisper) - Apple's MLX framework for efficient inference

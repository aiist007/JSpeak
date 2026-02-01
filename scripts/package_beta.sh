#!/usr/bin/env bash
set -euo pipefail

# JSpeak Beta packager
# - Builds release binary
# - Creates a self-contained .app bundle
# - Bundles Python service + requirements
# - Optionally bundles a local model snapshot

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

APP_NAME="JSpeak"
APP_BUNDLE_ID="com.jspeak.beta"
APP_VERSION="0.1"
APP_BUILD="3"

MODEL_DIR="${ROOT_DIR}/Assets/Models/whisper-medium"
WHEELHOUSE_DIR="${ROOT_DIR}/Assets/Wheelhouse"
PY_RUNTIME_DIR="${ROOT_DIR}/Assets/PythonRuntime"

cd "${ROOT_DIR}"

swift build -c release

OUT_DIR="${ROOT_DIR}/Build"
APP_DIR="${OUT_DIR}/JSpeakBeta.app"

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" \
         "${APP_DIR}/Contents/Resources/Python" \
         "${APP_DIR}/Contents/Resources/Models" \
         "${APP_DIR}/Contents/Resources/Wheelhouse" \
         "${APP_DIR}/Contents/Resources/PythonRuntime"

cp "${ROOT_DIR}/.build/arm64-apple-macosx/release/jspeak-ime-host" "${APP_DIR}/Contents/MacOS/JSpeakBeta"
cp "${ROOT_DIR}/Python/jsp_speech_service.py" "${APP_DIR}/Contents/Resources/Python/"
cp "${ROOT_DIR}/Python/requirements.txt" "${APP_DIR}/Contents/Resources/Python/"

if [[ -d "${MODEL_DIR}" ]]; then
  rm -rf "${APP_DIR}/Contents/Resources/Models/whisper-medium"
  cp -R "${MODEL_DIR}" "${APP_DIR}/Contents/Resources/Models/whisper-medium"
fi

if [[ -d "${WHEELHOUSE_DIR}" ]]; then
  rm -rf "${APP_DIR}/Contents/Resources/Wheelhouse"
  mkdir -p "${APP_DIR}/Contents/Resources/Wheelhouse"
  cp -R "${WHEELHOUSE_DIR}/." "${APP_DIR}/Contents/Resources/Wheelhouse/"
fi

if [[ -d "${PY_RUNTIME_DIR}" ]]; then
  rm -rf "${APP_DIR}/Contents/Resources/PythonRuntime"
  mkdir -p "${APP_DIR}/Contents/Resources/PythonRuntime"
  cp -R "${PY_RUNTIME_DIR}/." "${APP_DIR}/Contents/Resources/PythonRuntime/"
fi

cat > "${APP_DIR}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleExecutable</key>
  <string>JSpeakBeta</string>
  <key>CFBundleIdentifier</key>
  <string>${APP_BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${APP_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${APP_BUILD}</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>JSpeak 需要使用麦克风进行语音输入。</string>
</dict>
</plist>
EOF

# Ad-hoc sign for local beta distribution.
codesign --force --deep --sign - "${APP_DIR}"

# Create a distributable zip (keeps .app bundle structure).
rm -f "${OUT_DIR}/JSpeakBeta.zip"
ditto -c -k --sequesterRsrc --keepParent "${APP_DIR}" "${OUT_DIR}/JSpeakBeta.zip"

echo "Built: ${APP_DIR}"

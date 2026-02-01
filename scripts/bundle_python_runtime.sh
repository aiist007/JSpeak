#!/usr/bin/env bash
set -euo pipefail

# Bundle a Python runtime into Assets/PythonRuntime.
#
# Goal: recipients can run JSpeakBeta.app without installing python3.
#
# Usage (local directory):
#   JSPEAK_PY_RUNTIME_SRC=/path/to/python-runtime-root bash JSpeak/scripts/bundle_python_runtime.sh
#
# Usage (download archive):
#   JSPEAK_PY_RUNTIME_URL=https://.../python-...tar.gz bash JSpeak/scripts/bundle_python_runtime.sh
#
# Supported archive types: .tar.gz, .zip
#
# Expected runtime layout inside the app (we package under Contents/Resources/PythonRuntime):
#   PythonRuntime/bin/python3
#   PythonRuntime/lib/...
#
# Recommended source: a relocatable build like python-build-standalone.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/Assets/PythonRuntime"

SRC="${JSPEAK_PY_RUNTIME_SRC:-}"
URL="${JSPEAK_PY_RUNTIME_URL:-}"

TMP_DIR="${ROOT_DIR}/.tmp_python_runtime"

if [[ -z "${SRC}" && -z "${URL}" ]]; then
  echo "Missing JSPEAK_PY_RUNTIME_SRC or JSPEAK_PY_RUNTIME_URL." >&2
  echo "Example (local): JSPEAK_PY_RUNTIME_SRC=~/Downloads/python-runtime bash JSpeak/scripts/bundle_python_runtime.sh" >&2
  echo "Example (url):   JSPEAK_PY_RUNTIME_URL=https://.../python-...tar.gz bash JSpeak/scripts/bundle_python_runtime.sh" >&2
  exit 1
fi

if [[ -n "${URL}" ]]; then
  rm -rf "${TMP_DIR}"
  mkdir -p "${TMP_DIR}"
  ARCHIVE="${TMP_DIR}/runtime"
  echo "Downloading: ${URL}"
  curl -L --fail --retry 3 --connect-timeout 20 --max-time 0 "${URL}" -o "${ARCHIVE}"

  EXTRACT_DIR="${TMP_DIR}/extract"
  mkdir -p "${EXTRACT_DIR}"

  if [[ "${URL}" == *.tar.gz ]]; then
    tar -xzf "${ARCHIVE}" -C "${EXTRACT_DIR}"
  elif [[ "${URL}" == *.zip ]]; then
    ditto -x -k "${ARCHIVE}" "${EXTRACT_DIR}"
  else
    echo "Unsupported archive type (need .tar.gz or .zip): ${URL}" >&2
    exit 1
  fi

  # If the archive contains a single top-level directory, use it.
  TOP_COUNT=$(ls -1 "${EXTRACT_DIR}" | wc -l | tr -d ' ')
  if [[ "${TOP_COUNT}" == "1" ]]; then
    SRC="${EXTRACT_DIR}/$(ls -1 "${EXTRACT_DIR}")"
  else
    SRC="${EXTRACT_DIR}"
  fi
fi

if [[ ! -d "${SRC}" ]]; then
  echo "Runtime source is not a directory: ${SRC}" >&2
  exit 1
fi

if [[ ! -x "${SRC}/bin/python3" ]]; then
  echo "Expected executable not found: ${SRC}/bin/python3" >&2
  echo "Provide a runtime root that contains bin/python3." >&2
  exit 1
fi

rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"

cp -R "${SRC}/." "${OUT_DIR}/"

echo "Bundled python runtime: ${OUT_DIR}"

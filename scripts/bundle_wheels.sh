#!/usr/bin/env bash
set -euo pipefail

# Download python wheels into Assets/Wheelhouse for offline install.
# Uses the python specified by JSPEAK_PYTHON if set, otherwise tries common locations.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REQ_FILE="${ROOT_DIR}/Python/requirements.txt"
OUT_DIR="${ROOT_DIR}/Assets/Wheelhouse"

PYTHON_BIN="${JSPEAK_PYTHON:-}"
if [[ -z "${PYTHON_BIN}" ]]; then
  for c in "/opt/homebrew/opt/python@3.14/bin/python3.14" "/opt/homebrew/bin/python3" "/usr/bin/python3"; do
    if [[ -x "${c}" ]]; then
      PYTHON_BIN="${c}"
      break
    fi
  done
fi

if [[ -z "${PYTHON_BIN}" ]]; then
  echo "No python found. Set JSPEAK_PYTHON." >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"

"${PYTHON_BIN}" -m pip download -r "${REQ_FILE}" -d "${OUT_DIR}"

echo "Wheelhouse ready: ${OUT_DIR}"

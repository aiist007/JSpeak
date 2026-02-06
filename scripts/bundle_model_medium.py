#!/usr/bin/env python3

"""Download and bundle a local MLX Whisper model snapshot.

This script downloads the HuggingFace repo snapshot into:
  JSpeak/Assets/Models/whisper-medium

It is intended for packaging a beta app that works offline.

Note: Model size is large; expect a big app bundle.
"""

from __future__ import annotations

from pathlib import Path


def main() -> int:
    try:
        from huggingface_hub import snapshot_download
    except Exception as e:
        raise SystemExit(
            "huggingface_hub is required. Install it in your build python environment.\n"
            f"Error: {e}"
        )

    root = Path(__file__).resolve().parents[1]
    out_dir = root / "Assets" / "Models" / "whisper-medium"
    out_dir.parent.mkdir(parents=True, exist_ok=True)

    repo_id = "mlx-community/whisper-medium"
    print(f"Downloading {repo_id} -> {out_dir}")
    snapshot_download(
        repo_id=repo_id,
        local_dir=str(out_dir),
    )
    print("Done")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

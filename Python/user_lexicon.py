#!/usr/bin/env python3

import json
import os
import re
import time
from collections import Counter
from pathlib import Path
from typing import Dict, List, Optional, Set


class UserLexicon:
    def __init__(self, lexicon_path: Optional[str] = None):
        if lexicon_path:
            self.lexicon_path = Path(lexicon_path)
        else:
            support_dir = Path.home() / "Library" / "Application Support" / "JSpeak"
            support_dir.mkdir(parents=True, exist_ok=True)
            self.lexicon_path = support_dir / "user_lexicon.json"

        self.data = self._load()

    def _load(self) -> dict:
        if not self.lexicon_path.exists():
            return {
                "version": "1.0",
                "hotwords": {},
                "corrections": {},
                "transcripts": [],
                "stats": {"total_transcripts": 0, "last_hotword_update": 0},
            }
        try:
            with open(self.lexicon_path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return {
                "version": "1.0",
                "hotwords": {},
                "corrections": {},
                "transcripts": [],
                "stats": {"total_transcripts": 0, "last_hotword_update": 0},
            }

    def _save(self):
        try:
            with open(self.lexicon_path, "w", encoding="utf-8") as f:
                json.dump(self.data, f, ensure_ascii=False, indent=2)
        except Exception:
            pass

    def record_transcript(self, text: str):
        if not text or not text.strip():
            return

        timestamp = time.time()
        self.data["transcripts"].append({"text": text, "timestamp": timestamp})

        max_history = 500
        if len(self.data["transcripts"]) > max_history:
            self.data["transcripts"] = self.data["transcripts"][-max_history:]

        self.data["stats"]["total_transcripts"] = (
            self.data["stats"].get("total_transcripts", 0) + 1
        )

        self._extract_hotwords(text)

        if self._should_update_hotwords():
            self._update_hotword_prompt()

        self._save()

    def _extract_hotwords(self, text: str):
        candidates = self._find_word_candidates(text)

        for word in candidates:
            if word in self.data["hotwords"]:
                self.data["hotwords"][word]["count"] += 1
                self.data["hotwords"][word]["last_seen"] = time.time()
            else:
                self.data["hotwords"][word] = {"count": 1, "last_seen": time.time()}

    def _find_word_candidates(self, text: str) -> Set[str]:
        candidates = set()

        en_words = re.findall(r"\b[A-Z][A-Za-z0-9_\-]{2,}\b", text)
        candidates.update(en_words)

        acronyms = re.findall(r"\b[A-Z]{2,}\b", text)
        candidates.update(acronyms)

        mixed = re.findall(r"[A-Za-z]+[0-9]+|[0-9]+[A-Za-z]+", text)
        candidates.update(mixed)

        cn_en_phrases = re.findall(r"[\u4e00-\u9fff]{2,}[A-Za-z]{2,}", text)
        candidates.update(cn_en_phrases)

        return candidates

    def _should_update_hotwords(self) -> bool:
        total = self.data["stats"]["total_transcripts"]
        last_update = self.data["stats"].get("last_hotword_update", 0)
        return total - last_update >= 10

    def _update_hotword_prompt(self):
        try:
            support_dir = Path.home() / "Library" / "Application Support" / "JSpeak"
            prompt_path = support_dir / "prompt.txt"

            if not prompt_path.exists():
                return

            with open(prompt_path, "r", encoding="utf-8") as f:
                prompt = f.read()

            marker = "\n--- Personal Hotwords (auto-generated) ---\n"
            if marker in prompt:
                prompt = prompt.split(marker)[0]

            sorted_hotwords = sorted(
                self.data["hotwords"].items(), key=lambda x: x[1]["count"], reverse=True
            )

            top_hotwords = [w for w, _ in sorted_hotwords[:20] if len(w) >= 2]

            if top_hotwords:
                hotword_section = marker + ", ".join(top_hotwords) + "\n"
                prompt = prompt.rstrip() + "\n" + hotword_section

                with open(prompt_path, "w", encoding="utf-8") as f:
                    f.write(prompt)

            self.data["stats"]["last_hotword_update"] = self.data["stats"][
                "total_transcripts"
            ]
            self._save()
        except Exception:
            pass

    def apply_personalization(self, text: str) -> str:
        return text

    def get_top_hotwords(self, n: int = 20) -> List[str]:
        sorted_hotwords = sorted(
            self.data["hotwords"].items(), key=lambda x: x[1]["count"], reverse=True
        )
        return [w for w, _ in sorted_hotwords[:n]]

    def get_stats(self) -> dict:
        return {
            "total_transcripts": self.data["stats"]["total_transcripts"],
            "unique_hotwords": len(self.data["hotwords"]),
            "top_hotwords": self.get_top_hotwords(10),
        }

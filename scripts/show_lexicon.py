#!/usr/bin/env python3

import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "Python"))

from user_lexicon import UserLexicon


def main():
    lexicon = UserLexicon()
    stats = lexicon.get_stats()

    print("📊 JSpeak 个人词库统计")
    print("=" * 50)
    print(f"总转写次数: {stats['total_transcripts']}")
    print(f"学到的专有词: {stats['unique_hotwords']}")
    print()

    if stats["top_hotwords"]:
        print("🔥 Top 10 高频词:")
        for i, word in enumerate(stats["top_hotwords"], 1):
            count = lexicon.data["hotwords"][word]["count"]
            print(f"  {i:2}. {word:20} (出现 {count} 次)")
    else:
        print("还没有学到任何词，多说几句试试！")

    print()
    print(f"词库文件: {lexicon.lexicon_path}")


if __name__ == "__main__":
    main()

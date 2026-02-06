# JSpeak 个人词库学习系统

## 功能

JSpeak 会自动学习你的语音输入习惯，越用越准确。

### 自动学习内容

1. **专有词提取**
   - 大写开头的英文词（如 `Model`, `Tesla`, `OpenAI`）
   - 全大写缩写（如 `RAG`, `LLM`, `EBITDA`）
   - 中英混合词（如 `飞书`, `Feishu`）
   - 数字字母组合（如 `4680`, `V2G`）

2. **自动更新 Prompt**
   - 每 10 次转写后，自动把 Top 20 高频词追加到你的 `prompt.txt`
   - 下次转写时 Whisper 会优先识别这些词

3. **转写历史记录**
   - 保存最近 500 条转写记录
   - 用于未来的模式分析和优化

## 使用方法

### 正常使用

按住 Fn 说话，松开即可。**无需额外操作**，系统会自动学习。

### 查看学习效果

```bash
python3 scripts/show_lexicon.py
```

输出示例：

```
📊 JSpeak 个人词库统计
==================================================
总转写次数: 47
学到的专有词: 23

🔥 Top 10 高频词:
   1. OpenClaw             (出现 8 次)
   2. RAG                  (出现 7 次)
   3. Tesla                (出现 5 次)
   4. EBITDA               (出现 4 次)
   5. Model                (出现 4 次)
   ...

词库文件: ~/Library/Application Support/JSpeak/user_lexicon.json
```

### 手动查看/编辑词库

```bash
# 查看 JSON 原始数据
cat ~/Library/Application\ Support/JSpeak/user_lexicon.json

# 查看自动生成的热词（已追加到 prompt）
cat ~/Library/Application\ Support/JSpeak/prompt.txt
```

### 重置学习数据

```bash
# 删除词库重新开始
rm ~/Library/Application\ Support/JSpeak/user_lexicon.json

# 删除个性化 prompt（会恢复默认）
rm ~/Library/Application\ Support/JSpeak/prompt.txt
```

## 工作原理

1. 每次转写完成后，Python 服务自动提取潜在的专有词
2. 记录到本地 JSON 文件（`user_lexicon.json`）
3. 每 10 次累积后，把 Top 20 高频词追加到 `prompt.txt`
4. 下次转写时，Whisper 会读取更新后的 prompt，优先识别这些词

## 隐私

- **完全本地**：所有数据存储在 `~/Library/Application Support/JSpeak/`
- **不上云**：无任何网络传输
- **可随时删除**：删除 `user_lexicon.json` 即可清空学习数据

## 未来优化方向

- [ ] 纠错记忆（检测重复说同一个词的纠错行为）
- [ ] 标点习惯学习（基于停顿时长）
- [ ] 问句模式识别（基于语气词统计）
- [ ] 上下文感知替换（同一个词在不同场景的不同拼写）

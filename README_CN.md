# JSpeak

本地优先的 macOS 语音输入工具，基于 Apple Silicon 运行，包含菜单栏应用和本地语音引擎。它不仅能听懂你的话，还能**自动学习**你的词汇习惯。

[![GitHub Release](https://img.shields.io/github/v/release/aiist007/JSpeak)](https://github.com/aiist007/JSpeak/releases)
[![Swift 版本](https://img.shields.io/badge/Swift-6.0-orange)](https://swift.org)
[![Python](https://img.shields.io/badge/Python-3.14-blue)](https://python.org)

## ✨ 最新功能 (v0.2.0)

- 🧠 **个人词库自动学习** - 自动提取你常说的专有词、缩写和中英混合词，越用越准
- 🇨🇳 **中文标点优化** - 智能补全逗号、句号和问号，不再需要一口气说完
- 📝 **自定义提示词** - 菜单栏一键打开 `prompt.txt`，随时添加你的专属热词
- 🔌 **兼容性增强** - 完美支持 VSCode、Cursor、Electron 等开发工具（自动切换 Paste 模式）

## 核心特性

- 🎤 **本地语音识别** - MLX-Whisper 完全在 Mac 上运行（不上云）
- ⌨️ **全局热键** - 按住 Fn 或 F6 随时语音输入
- 🔒 **隐私优先** - 所有数据（包括学习的词库）绝不离开你的机器
- ⚡ **快速启动** - 模型在启动时预加载，按下即录

## 系统要求

- macOS 13.0+ Apple Silicon（M1/M2/M3）
- Python 3.14（可选，发行版已内置）
- Whisper Medium 模型约需 4GB 内存

## 快速开始

### 下载发行版（推荐）

1. 从 [Releases](https://github.com/aiist007/JSpeak/releases) 下载 `JSpeakBeta.zip`
2. 或从夸克网盘下载：[点击跳转](https://pan.quark.cn/s/bc26582e2311?pwd=4s2V) (提取码：4s2V)
3. 解压并将 `JSpeakBeta.app` 移到 `/Applications`
4. 首次运行时授予权限：
   - **麦克风**
   - **辅助功能**（用于文本注入）
   - **输入监控**（用于全局热键）

### 从源码编译

```bash
git clone https://github.com/aiist007/JSpeak.git
cd JSpeak

# 构建发行版
bash scripts/package_beta.sh

# 或运行 CLI 测试
swift run jspeak -- ping
```

## 使用方法

1. **启动 JSpeak** - 点击菜单栏的 JSpeak 图标
2. **按住 Fn** 录音，**松开 Fn** 转写
3. **F6** 作为备用热键
4. **编辑热词** - 点击菜单栏 "Open Prompt…" 手动添加词汇

### 🧠 自动学习系统

JSpeak 会在后台自动学习你的输入习惯（完全本地）：

1. **自动提取**：识别大写英文（Tesla）、缩写（RAG）、中英混合词（Feishu）
2. **自动优化**：每 10 次转写，自动将高频热词追加到识别提示词中
3. **查看效果**：运行以下命令查看你“教会”了 JSpeak 多少词：

```bash
python3 scripts/show_lexicon.py
```

*数据存储在 `~/Library/Application Support/JSpeak/user_lexicon.json`，随时可删。*

### 语音命令

| 短语 | 操作 |
|------|------|
| 换行 / new line | 插入换行 |
| 删除 / delete | 删除上一个词 |
| 句号 / period | 结束句子 |

## 项目架构

```
JSpeak/
├── Sources/JSpeakIMEHost/         # Swift 菜单栏应用 (AppKit)
├── Sources/JSpeakPythonBridge/    # Swift-Python IPC 桥接
├── Python/
│   ├── jsp_speech_service.py      # MLX-Whisper 语音引擎
│   └── user_lexicon.py            # 本地词库学习模块
├── Assets/
│   ├── Models/whisper-medium/     # 内置 Whisper 模型
│   └── PythonRuntime/             # 嵌入式 Python 3.14
└── scripts/
    └── show_lexicon.py            # 词库统计工具
```

## 常见问题

**VSCode / Cursor 无法输入？**
- 新版本已自动修复此问题（自动检测 Electron 应用并切换为 Cmd+V 粘贴模式）。

**转写没有标点？**
- 请尝试说完整句子。新版已增强了对问句和长句停顿的标点补全。

**如何重置学习数据？**
- 删除 `~/Library/Application Support/JSpeak/user_lexicon.json` 即可。

## 许可证

MIT License - 详见 [LICENSE](LICENSE)。

## 致谢

- [MLX-Whisper](https://github.com/mlx-community/whisper) - Apple MLX 高效推理框架

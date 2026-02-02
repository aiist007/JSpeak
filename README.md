# JSpeak

本地优先的 macOS 语音输入工具，基于 Apple Silicon 运行，包含菜单栏应用和本地语音引擎。

[![GitHub Release](https://img.shields.io/github/v/release/aiist007/JSpeak)](https://github.com/aiist007/JSpeak/releases)
[![Swift 版本](https://img.shields.io/badge/Swift-6.0-orange)](https://swift.org)
[![Python](https://img.shields.io/badge/Python-3.14-blue)](https://python.org)

## 功能特性

- 🎤 **本地语音识别** - MLX-Whisper 完全在 Mac 上运行（不上云）
- ⌨️ **全局热键** - 按住 Fn 随时语音输入，结合vibe coding真正实现了用嘴编程
- 🔒 **隐私优先** - 数据绝不离开你的机器
- 🇨🇳🇺🇸 **中英双语支持** - 混合中英文识别
- 📝 **智能标点** - 自动检测问句并添加标点
- ⚡ **快速启动** - 模型在启动时预加载

## 系统要求

- macOS 13.0+ Apple Silicon（M1/M2/M3）
- Python 3.14（可选，发行版已内置）
- Whisper Medium 模型约需 4GB 内存

## 快速开始

### 下载发行版（推荐）

1. 从 [夸克网盘](https://pan.quark.cn/s/bc26582e2311?pwd=4s2V) (提取码：4s2V) 下载 `JSpeakBeta.zip`
2. 解压并将 `JSpeakBeta.app` 移到 `/Applications`
3. 首次运行时授予权限：
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
4. 直接在任何文本框中语音输入

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
├── Sources/JSpeakCLI/             # CLI 测试工具
├── Python/
│   └── jsp_speech_service.py      # MLX-Whisper 语音引擎
├── Assets/
│   ├── Models/whisper-medium/     # 内置 Whisper 模型
│   └── PythonRuntime/             # 嵌入式 Python 3.14
└── scripts/
    └── package_beta.sh            # 应用打包脚本
```

## 开发指南

### Python 服务（独立测试）

```bash
# 麦克风测试
python3 Python/jsp_mic_client.py --mixed

# CLI ping 测试
python3 Python/jsp_test_client.py ping
```

### Swift 开发

```bash
# 调试构建
swift build

# 运行 CLI
swift run jspeak -- ping

# 构建发行版
swift build -c release
```

## 权限说明

JSpeak 需要以下 macOS 权限：

| 权限 | 用途 |
|------|------|
| 麦克风 | 录制音频进行转写 |
| 辅助功能 | 向应用注入识别文本 |
| 输入监控 | 检测全局 Fn/F6 热键 |

## 常见问题

**首次运行转写失败？**
- 等待 Python 环境配置（可能需要一分钟）
- 检查是否安装 Python 或使用内置版本

**文本没有出现？**
- 确保已授予辅助功能权限
- 尝试先点击目标文本框

**Fn 键不工作？**
- 检查系统设置 → 键盘 → 键盘快捷键 → 功能键
- 使用 F6 作为备用方案

## 许可证

MIT License - 详见 [LICENSE](LICENSE)。

## 致谢

- [MLX-Whisper](https://github.com/mlx-community/whisper) - Apple MLX 高效推理框架

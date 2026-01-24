# 🚀 NeoHubR

<p align="center">
<img width="757" height="418" alt="NeoHubR Demo" src="https://github.com/user-attachments/assets/724d0e7f-ca91-4759-9e15-5005f82038fc" />
</p>

<p align="center">
<strong>给 macOS 上的 Neovide 加点“超能力” ⚡️</strong>
</p>

<p align="center">
<a href="README.md">English</a>
</p>

---

**NeoHubR**（**Reboot**）是一款专为 macOS 设计的菜单栏常驻工具，它是 **Neovide** 的最佳拍档。它不仅能帮你管理凌乱的编辑器窗口，还能通过丝滑的快捷键让你在项目间瞬间移动。

## 📸 预览

<p align="center">
<img width="411" height="474" alt="NeoHubR Screenshot 1" src="https://github.com/user-attachments/assets/eaf9400f-1ee9-4522-9048-1039604c8a6e" />
<img width="411" height="474" alt="NeoHubR Screenshot 2" src="https://github.com/user-attachments/assets/8257b402-1d5d-4f86-9fdd-c509d59650cd" />
</p>

## ✨ 功能亮点

* **🖱️ 菜单栏工作流**: 轻轻一点，所有运行中的编辑器尽在掌握。
* **⌨️ 丝滑切换**: 全局快捷键唤起切换器，在不同项目间“闪现”。
* **🚀 智能启动 (CLI)**: 告别重复启动！通过命令行打开项目时，如果该项目已运行，NeoHubR 会直接激活它。
* **📂 项目管理**: 内置收藏（Starred）与最近项目（Recent）列表，找代码不再大海捞针。
* **🔄 一键重连**: 专属快捷键快速重启当前编辑器。
* **🔔 状态感知**: 完美的系统级通知，实时同步 CLI 和编辑器状态。
* **🎨 原生质感**: 采用最新 SwiftUI 构建，支持 Liquid Glass 视觉效果，完美适配 macOS 现代美学。

## 🤔 为什么要用 NeoHubR?

Neovide 确实很棒，但在 macOS 上有两个让人头疼的痛点：

1. **窗口分不清**: 开启多个实例后，在 `⌘⇥` 切换时看到的都是一样的图标和名字，找起窗口来全靠猜。
2. **Swap 文件冲突**: 经常不小心在不同窗口重复打开同一个项目，导致烦人的 Swap 报错。

**NeoHubR 为此而生：它让 Neovide 拥有了像现代 IDE 一样的项目管理体验。**

## 🛠️ 安装与要求

* **系统**: macOS 14+ (Sonoma 或更高)
* **环境**: 确保 `neovide` 已在你的 `PATH` 中
* **核心**: 安装 App 后，请在 **Settings** 中点击安装 **CLI** 工具（这是灵魂所在）。

### 开始使用

1. 前往 [Releases](https://github.com/micsama/NeoHubR/releases) 下载最新 `.dmg`。
2. 拖拽 `NeoHubR.app` 到 `/Applications`。
3. **初次启动提示**: 由于该版本未进行公证（Notarized），如果 macOS 拦截，请在 Finder 中**右键点击 -> 打开**，或在“系统设置 -> 隐私与安全性”中选择允许。

## 💡 玩转 NeoHubR

### 命令行 (CLI)

在终端里用 `neohubr` 代替 `neovide` 命令。它会自动帮你去重并聚焦已有窗口。

### 快捷键 (默认)

* `⌃ + \``: 唤起项目切换器。
* `⌘ ⌃ Z`: 快速回到上一个编辑器。
* **在切换器中**:
* `⇥ (Tab)` / `shift + ⇥ (Tab)`: 循环切换。
* `⌘ Q`: 关闭所有编辑器。
* `⌘ ⌫`: 关闭当前选中的编辑器。



> [!TIP]
> 大部分的快捷键都可以在 Settings 页面根据你的习惯自定义，少部分的后续会补充～

## 🏗️ 本地构建

```bash
open NeoHubR.xcodeproj
# 分别构建主程序和 CLI 工具
xcodebuild -project NeoHubR.xcodeproj -scheme NeoHubR -configuration Debug build
xcodebuild -project NeoHubR.xcodeproj -scheme NeoHubRCLI -configuration Debug build

```

## 🧭 路线图（简版）

- **v0.3.1**：Switcher 循环导航 + 搜索高亮；项目去重（真实路径）；Recent/Star 删除；启动/打开时检测失效项目并置灰；从 Switcher 打开失效项目时发系统通知。
- **v0.4.0**：Projects 手动添加（目录 / Session.vim）；Session 项目标注；项目自定义图标/颜色并在 Switcher 展示。
- **v0.4.1**：运行中 Neovide 实例接管（混合方案）；GUI 启动环境继承（默认每次从 Switcher 打开时继承，具体实现待评估）。
- **v0.5.0**：Switcher 视觉与交互体验整体优化。

## 🤝 致谢

* App 图标设计: [u/danbee](https://www.reddit.com/user/danbee/)
* 灵感来源: [alex35mil/NeoHub](https://github.com/alex35mil/NeoHub)
## 📄 开源协议

本项目采用 **MIT License**。

Copyright (c) 2024-2026 YourName.

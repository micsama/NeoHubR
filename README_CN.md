# NeoHub

> English: [README.md](README.md)

<p align="center">
    <!-- 图片占位，后续替换 -->
    <!-- <img width="720" alt="NeoHub" src="YOUR_IMAGE_URL"> -->
</p>

---

NeoHub（应用内显示名 **NeoHubR**）是 **Neovide** 的 macOS 菜单栏助手。  
本 README 先聚焦 **用户可感知的功能**。

## 功能（用户视角）
- **菜单栏工作流**：常驻入口、编辑器列表与快捷操作。
- **切换器**：全局快捷键呼出并在多个编辑器之间跳转。
- **智能启动**：CLI 按路径去重，发现已有实例则直接激活。
- **项目注册表**：Starred / Recent 项目列表贯穿切换器与设置。
- **重启快捷键**：一键重启当前编辑器。
- **系统通知**：清晰的 CLI 与编辑器生命周期通知。
- **原生设置**：SwiftUI Settings Scene，分 General / Projects / Advanced。
- **Liquid Glass 方向**：现代 macOS 视觉风格并带降级方案。

## 为什么需要它
Neovide 很棒，但在 macOS 上：
1. 多个实例在 `⌘⇥` 里都叫 `neovide`，难以区分。
2. 重复进入同一项目容易触发 swap 文件冲突。

## 运行要求
- macOS 14+
- `PATH` 中可用 `neovide`
- 首次运行在设置中安装 CLI

## 安装
从 GitHub Releases 下载最新 `.dmg`（或使用 Xcode 本地编译）。  
打开 DMG，将 `NeoHub.app` 拖入 `/Applications` 后启动。  
首次启动后在设置中安装 CLI。

提示：此版本未公证（Notarized）。  
若系统拦截，请右键应用 → 打开，或在“系统设置 → 隐私与安全性”中允许打开。

## 使用
**CLI**  
使用 `neohub` 启动编辑器，会按路径去重并激活已存在的实例。

**App**
- `⌘⌃N` 打开切换器
- `⌘⌃Z` 激活最近编辑器
- 所有快捷键可在设置中配置
- 切换器支持 `⌘Q`（退出全部）、`⌘⌫`（退出选中）、`⇥`（循环）

## 构建
```bash
open NeoHub.xcodeproj
xcodebuild -project NeoHub.xcodeproj -scheme NeoHub -configuration Debug build
xcodebuild -project NeoHub.xcodeproj -scheme NeoHubCLI -configuration Debug build
```

## 致谢
- 图标作者：u/danbee
- 原始项目：alex35mil/NeoHub（fork 后重构）

## 许可
MIT

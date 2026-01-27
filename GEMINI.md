# NeoHubR 上下文
## 补充信息
用中文和用户交流

## 项目概述

**NeoHubR** (Reboot) 是一款专为 **Neovide** 设计的 macOS 菜单栏辅助工具，旨在优化窗口管理和项目切换。它作为 Neovide 的包装器（Wrapper），提供以下功能：

* **实例去重：** 通过命令行（`nh`）打开项目时，如果已存在该实例，则直接聚焦。
* **项目切换器：** 一个名为 "Teleport" 的可视化界面，用于在活跃项目间切换。
* **项目注册表：** 追踪最近打开和星标（收藏）的项目。
* **套接字通信：** 使用 UNIX 域套接字（UNIX domain socket）实现 CLI 工具与主程序之间的通信。

## 架构设计

项目由三个主要组件组成：

1. **NeoHubR (App):**
* **类型：** macOS 应用 (SwiftUI + AppKit)。
* **职责：** 服务器端及图形界面。管理菜单栏图标、切换器窗口以及后台套接字服务器 (`SocketServer.swift`)。
* **入口点：** `NeoHubR/App/App.swift`。
* **核心组件：** `EditorStore` (状态管理)、`SwitcherWindow` (UI)、`SocketServer` (IPC)。


2. **NeoHubRCLI (CLI):**
* **类型：** 命令行工具。
* **职责：** 客户端 (`nh` 命令)。解析参数并通过套接字向 App 发送运行请求。
* **入口点：** `NeoHubRCLI/CLI.swift` (使用 `ArgumentParser`)。
* **通信：** 连接至 `/tmp/neohubr.sock`。


3. **NeoHubRLib (共享库):**
* **类型：** 共享框架/源码。
* **职责：** 包含共享类型、常量和逻辑，确保 App 与 CLI 之间的一致性。
* **内容：** IPC 协议 (`Shared.swift`, `IPCTools.swift`)、设置 (`AppSettings.swift`) 及项目逻辑 (`ProjectRegistry.swift`)。



## 构建与运行

**前提条件：**

* macOS 14+ (Sonoma 或更高版本)。
* 已安装 `neovide` 并已添加至 `PATH`。
* Xcode 15+ (由 Swift 版本/macOS 目标版本要求)。

**构建命令：**
使用 `xcodebuild` 分别构建各目标：

```bash
# 构建主应用
xcodebuild -project NeoHubR.xcodeproj -scheme NeoHubR -configuration Debug build

# 构建 CLI 工具
xcodebuild -project NeoHubR.xcodeproj -scheme NeoHubRCLI -configuration Debug build

```

**运行方式：**

1. 运行应用：打开 `NeoHubR.app` (通常在构建产物目录中)。
2. 安装 CLI：在应用设置中点击 "Install CLI"。
3. 使用 CLI：在项目目录中运行 `nh .`。

## 目录结构

* **`NeoHubR/`**：主 macOS 应用程序源码。
* `App/`：生命周期与主控制器 (`App.swift`, `AppDelegate`, `CLI.swift` 包装器)。
* `Core/`：业务逻辑 (`EditorStore`, `SwitcherLogic`)。
* `views/`：SwiftUI 视图 (`MenuBarView`, `SwitcherView`, `SettingsView`)。
* `Support/`：工具类 (`Logger`, `NotificationManager`)。


* **`NeoHubRCLI/`**：`nh` 命令行工具源码。
* `CLI.swift`：参数解析与执行主逻辑。
* `SocketClient.swift`：与 App 通信的网络逻辑。


* **`NeoHubRLib/`**：共享代码。
* `Shared.swift`：套接字地址与请求结构体。
* `AppSettings.swift`：集中化的设置管理。



## 开发规范

* **格式化：** 项目使用 `.swift-format` 文件。确保代码符合规范（行宽 120 字符，4 空格缩进）。
* **共享逻辑：** 当修改 CLI 与 App 之间共享的数据结构或逻辑（如 IPC 消息、设置键名）时，**务必**修改 `NeoHubRLib`。
* **IPC：** 通信基于 UNIX 套接字上的 JSON 格式。协议的任何变更必须体现在 `NeoHubRLib` 中。
* **本地化：** 应用支持多语言（英文和简体中文）。请查看 `NeoHubR/Resources/Localization`。

## 关键技术

* **SwiftUI：** 主要 UI 框架。
* **AppKit：** 用于 SwiftUI 无法完全胜任的窗口管理和菜单栏交互。
* **Network.framework：** 用于 `SocketClient` 中的底层套接字通信。
* **Swift Argument Parser：** 用于 CLI 参数解析。

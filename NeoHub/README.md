# NeoHub (App)

该目录包含 macOS 菜单栏应用的主体实现（SwiftUI + AppKit）。

## 工作域
- 以菜单栏 App 形式运行，提供 Neovide 实例管理能力（切换、激活、重启）。
- 管理全局快捷键、窗口展示、通知、日志、CLI 安装状态与安装流程。
- 通过 UNIX domain socket 接收 CLI 发来的启动请求，并创建/激活 Neovide 进程。

## 关键入口与模块
- 入口：`App.swift`
  - `@main` + `AppDelegate` 初始化核心服务。
  - 绑定菜单栏 UI：`MenuBarView`。
- 进程/实例管理：`EditorStore.swift`
  - 维护 `Editor` 列表与排序逻辑。
  - 负责启动、激活、重启 Neovide 进程。
  - 启动/激活时记录最近项目到 `ProjectRegistry`。
- 激活与主线程工具：`AppUtilities.swift`
  - `ActivationManager` 记录/恢复前台应用与窗口（用于切换器隐藏后的回切）。
  - `MainThread` 提供主线程断言与调度。
- IPC：`SocketServer.swift`
  - 使用 Network.framework 监听 `/tmp/neohub.sock`，接收 CLI 请求并调用 `EditorStore.runEditor`。
- CLI 安装管理：`CLI.swift`
  - 通过 AppleScript 复制二进制与框架到 `/usr/local`。
- 窗口体系：`RegularWindow.swift` + `views/`
  - Switcher 窗口为浮层；设置/安装/关于为独立窗口。
  - RegularWindow 打开时会在当前屏幕居中，且同类窗口保持单实例。
- 设置模型：`NeoHubLib/AppSettings.swift`
  - 统一 App 侧设置 Key、默认值与可用性判断。
  - `AppSettingsStore` 作为可观察模型注入 Settings/Switcher。
- 通知与报告：`NotificationManager.swift`、`BugReporter.swift`
  - 运行时错误通知、用户反馈入口。
- 日志：`Logger.swift`
  - 使用 `NeoHubLib.Logger`（基于 `os.Logger`）。

## 典型运行流程
1. App 启动后初始化 SocketServer 并注册通知代理。
2. CLI 通过 socket 发送 `RunRequest`，App 解码并启动/激活 Neovide。
3. 用户使用快捷键显示切换器或激活上一次编辑器。

## 相关子模块
- 视图：`NeoHub/views/`（菜单栏、切换器、设置、安装、关于等）

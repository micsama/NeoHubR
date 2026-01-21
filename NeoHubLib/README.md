# NeoHubLib

该目录提供 App 与 CLI 共享的类型与常量，避免两端协议不一致。

## 工作域
- 定义 IPC 相关的共享协议结构。
- 提供统一的 socket 地址常量。
- 提供 App 侧设置模型，避免 key/默认值分散。

## 关键内容
- `Shared.swift`
  - `Socket.addr`：UNIX socket 路径（`/tmp/neohub.sock`）。
  - `RunRequest`：CLI -> App 的请求数据结构（工作目录、binary、路径、参数、环境变量）。
- `AppSettings.swift`
  - `AppSettings`：设置 key、默认值注册与可用性判断。
  - `AppSettingsStore`：App 使用的可观察设置模型（写回 UserDefaults）。

## 使用方式
- App/CLI 通过 SwiftPM 引用 NeoHubLib，统一请求/响应结构。

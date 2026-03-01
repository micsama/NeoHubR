# NeoHubRLib

该目录提供 App 与 CLI 共享类型与基础能力。

## 工作域
- 定义 App 与 CLI 共用的数据结构。
- 提供 App 侧设置模型，避免 key/默认值分散。

## 关键内容
- `Shared.swift`
  - `RunRequest`：Neovide 启动请求结构（工作目录、binary、路径、参数、环境变量）。
- `AppSettings.swift`
  - `AppSettings`：设置 key、默认值注册与可用性判断。
  - `AppSettingsStore`：App 使用的可观察设置模型（写回 UserDefaults）。
- 追加设置项：Switcher 最大展示条数（3~10）。
- `EditorNamingPolicy.swift`
  - `EditorNamingPolicy`：统一实例命名与路径归一逻辑，便于后续扩展单文件/项目命名策略。
- `ProjectRegistry.swift`
  - `ProjectEntry`：项目条目（路径、展示名、图标、颜色、最近打开时间、收藏/排序）。
  - `ProjectRegistry`：UserDefaults 序列化读写入口。
  - `ProjectRegistryStore`：App 侧可观察项目列表。
## 使用方式
- App/CLI 通过 SwiftPM 引用 NeoHubRLib，统一数据模型与工具逻辑。

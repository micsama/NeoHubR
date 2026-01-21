# NeoHub Views

该目录包含 NeoHub 的主要 SwiftUI 视图。

## 视图列表与职责
- `MenuBarView.swift`
  - 菜单栏下拉菜单：列出编辑器、设置/关于入口、CLI 状态与安装按钮。
- `SwitcherView.swift`
  - 编辑器切换器主界面与热键处理；管理切换/激活逻辑。
  - 提供 Legacy 与 macOS 26 Liquid Glass 双 UI 模式（设置中切换）。
  - 支持 Tab 循环与 `⌘1~⌘9` 快捷切换（列表右侧显示提示）。
- `SettingsView.swift`
  - 应用设置与热键设置；启动项开关、CLI 安装/卸载入口。
  - Liquid Glass 开关在 macOS 26+ 可用；低版本置灰。
- `InstallationView.swift`
  - CLI 安装/更新/错误引导窗口；提供安装按钮与状态反馈。
- `AboutView.swift`
  - 应用信息与版本展示。

## 典型交互
- 快捷键触发 `SwitcherView`，展示编辑器列表并激活目标编辑器。
- `MenuBarView` 中根据 CLI 状态显示安装/更新提示。

# NeoHub Views

该目录包含 NeoHub 的主要 SwiftUI 视图。

## 视图列表与职责
- `MenuBarView.swift`
  - 菜单栏下拉菜单：列出编辑器、设置/关于入口、CLI 状态与安装按钮。
- `SwitcherView.swift`
  - 编辑器切换器主界面与热键处理；管理切换/激活逻辑。
- `SettingsView.swift`
  - 应用设置与热键设置；启动项开关、CLI 安装/卸载入口。
- `InstallationView.swift`
  - CLI 安装/更新/错误引导窗口；提供安装按钮与状态反馈。
- `AboutView.swift`
  - 应用信息与版本展示。

## 典型交互
- 快捷键触发 `SwitcherView`，展示编辑器列表并激活目标编辑器。
- `MenuBarView` 中根据 CLI 状态显示安装/更新提示。

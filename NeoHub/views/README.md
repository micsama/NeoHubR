# NeoHub Views

该目录包含 NeoHub 的主要 SwiftUI 视图。

## 视图列表与职责
- `MenuBarView.swift`
  - 菜单栏下拉菜单：列出编辑器、设置/关于入口、CLI 状态与安装按钮。
- `SwitcherView.swift`
  - 编辑器切换器主界面与热键处理；管理切换/激活逻辑。
  - 统一使用 Liquid Glass 视觉风格；macOS 26 自动启用玻璃效果，旧版本采用兼容背景。
  - 支持 Tab 循环与 `⌘1~⌘0` 快捷切换（列表右侧显示提示）。
  - 列表可混合展示已打开编辑器与最近项目（不足 N 条时补齐）。
- `SettingsView.swift`
  - 应用设置与热键设置；启动项开关、CLI 安装/卸载入口。
  - Projects 选项卡：显示/收藏项目、调整收藏排序、设置 Switcher 显示条数。
  - Advanced 页：窗口置顶开关与 CLI 错误提示开关。
- `InstallationView.swift`
  - CLI 安装/更新/错误引导窗口；提供安装按钮与状态反馈。
- `AboutView.swift`
  - 应用信息与版本展示。

## 典型交互
- 快捷键触发 `SwitcherView`，展示编辑器列表并激活目标编辑器。
- `MenuBarView` 中根据 CLI 状态显示安装/更新提示。

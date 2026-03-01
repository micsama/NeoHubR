# NeoHubRCLI

该目录包含命令行工具 `nh` 的实现，用于直接启动 Neovide。

## 工作域
- 解析 CLI 参数与选项并传递给 Neovide。
- 负责从 PATH 中定位 `neovide` 可执行文件。
- 使用 `NeoHubRLib.Logger` 统一日志能力。

## 关键文件
- `CLI.swift`
  - 基于 `ArgumentParser` 解析参数。
  - 直接启动 `neovide` 进程并等待退出状态。
  - 使用 `NeoHubRLib.Logger.bootstrap`，读取 `NEOHUBR_LOG` 设置日志级别。

## 典型流程
1. 用户在项目目录运行 `nh`。
2. CLI 查找 `neovide` 路径并拼装命令行参数。
3. 直接启动 `neovide`。

# NeoHubCLI

该目录包含命令行工具 `neohub` 的实现，用于启动或激活 Neovide 实例。

## 工作域
- 解析 CLI 参数与选项，构造 `RunRequest`。
- 通过 UNIX domain socket 与 NeoHub App 通信。
- 负责从 PATH 中定位 `neovide` 可执行文件。

## 关键文件
- `CLI.swift`
  - 基于 `ArgumentParser` 解析参数。
  - 构造 `RunRequest` 并调用 `SocketClient`。
- `SocketClient.swift`
  - 连接 `/tmp/neohub.sock` 并发送 JSON 请求。
  - 处理 App 的响应。
- `Shell.swift`
  - 用 `/bin/sh -c` 运行 `command -v neovide` 获取路径。
- `Logger.swift`
  - 读取 `NEOHUB_LOG` 环境变量设置日志级别。

## 典型流程
1. 用户在项目目录运行 `neohub`。
2. CLI 查找 `neovide` 路径并构造 `RunRequest`。
3. 通过 socket 将请求发送给 NeoHub App。

This release brings a massive internal refactoring to modernize the codebase, improve performance, and enhance security.

## 🚀 Key Improvements
*   **Architecture Modernization**: The entire app has been refactored to use Swift Concurrency (`async`/`await`), moving away from legacy GCD patterns. This improves thread safety and performance.
*   **Multi-User Security**: The IPC socket path is now isolated by user ID (`/tmp/neohubr-<uid>.sock`), preventing permission conflicts in multi-user environments.
*   **CLI Overhaul**: The `nh` CLI tool has been rewritten for native performance, removing external shell dependencies and utilizing efficient asynchronous communication.
*   **Codebase Cleanup**: Massive reduction in file fragmentation and code redundancy.

## ✨ Enhancements
*   **Switcher**: Optimized default shortcut to `Ctrl + ` ` (Backtick) for quicker access.
*   **Project Icons**: Improved logic for rendering project icons and emojis.
*   **Path Handling**: Unified path normalization logic across the entire application for consistent behavior.

## 🐞 Bug Fixes
*   Fixed concurrency warnings and improved stability of the notification system.
*   Improved robustness of active editor state persistence (now using proper temporary directories).

# 🚀 NeoHubR

<p align="center">
<img width="757" height="418" alt="switcher" src="https://github.com/user-attachments/assets/db0dbfe4-6e72-4f8a-8afe-deea013b0119" />
</p>

<p align="center">
<strong>Give your Neovide "Superpowers" on macOS ⚡️</strong>
</p>

<p align="center">
<a href="README_CN.md">简体中文</a>
</p>

---

**NeoHubR** (**Reboot**) is a modern, feature-packed reincarnation of [NeoHub](https://github.com/alex35mil/NeoHub).
Rebuilt from the ground up with **SwiftUI** and **Swift 6 Concurrency**, it transforms Neovide on macOS into a powerhouse with IDE-like project management.

## 🌟 What's New in Reboot?

Unlike the original tool which hasn't been updated in years, NeoHubR brings:

1.  **🗂️ Advanced Project Management**:
    *   **History & Stars**: Track recent projects and pin your favorites.
    *   **Customization**: Set custom names, icons (SF Symbols/Emoji), and highlight colors for each project.
2.  **🧠 Session Awareness**: First-class support for `Session.vim`. Opening a directory with a session file just works.
3.  **🧟 Instance Resurrection**: Restart NeoHubR (or crash recover), and it will automatically reconnect to all your running Neovide instances. No more lost windows.
4.  **⚡ Modern & Beautiful**: Completely rewritten using the latest macOS APIs. It's faster, safer, and looks stunning with "Liquid Glass" visuals.

> [!IMPORTANT]
> **Why use the CLI (`nh`)?**
> macOS GUI apps often struggle to inherit your shell's environment variables (like `PATH`, `LSP` setups).
> By running `nh .` from your terminal, NeoHubR captures your **exact shell environment** and passes it to Neovide. This ensures your plugins and tools work perfectly.

## 📸 Screenshots

<p align="center">
<img width="386" height="469" alt="settings" src="https://github.com/user-attachments/assets/ef1c9703-de15-427e-ae74-8271873acd3f" />
<img width="386" height="469" alt="projects" src="https://github.com/user-attachments/assets/99d8eb47-be4f-4a5f-b422-7bb524ce7cf0" />
<img width="291" height="418" alt="editor" src="https://github.com/user-attachments/assets/96c7a97d-993c-409e-b99e-4e4b07f3ad05" />
</p>

## ✨ Feature Highlights

* **🖱️ Menu Bar Workflow**: Instant access to all running editors with a single click.
* **⌨️ Seamless Switcher**: `⌃ + \`` (Ctrl + Backtick) to summon a global switcher to "teleport" between different projects.
* **🚀 Smart Launch (CLI)**: Stop duplicating! Opening a project via CLI will automatically re-activate the existing instance if it’s already running.
* **📂 Project Registry**: Keep your workspace organized with Starred and Recent project lists integrated directly into the switcher.
* **🔄 Quick Restart**: `⌃ + ⌘ + R` to restart your current editor instance instantly.
* **🔔 Native Notifications**: Stay informed with clean system notifications for CLI and editor lifecycle events.
* **🎨 Modern macOS Aesthetic**: Built with SwiftUI and featuring "Liquid Glass" visuals—it looks and feels like a native part of your Mac.

## 🤔 Why NeoHubR?

Neovide is amazing, but it has two major "quality of life" issues on macOS:

1. **Window Identity Crisis**: When running multiple instances, every process shows up as just `neovide` in `⌘⇥`. It’s a guessing game to find the right project.
2. **Swap File Conflicts**: Re-opening an existing project by mistake often leads to those annoying swap-file errors.

**NeoHubR solves this by bringing a modern IDE-like project management experience to Neovide.**

## 🛠️ Requirements & Setup

* **System**: macOS 14+ (Sonoma or later)
* **Environment**: `neovide` must be in your `PATH`
* **Core**: After installing the app, remember to click **Install CLI** in Settings (this is where the magic happens).

### Installation

1. Download the latest `.dmg` from [Releases](https://github.com/micsama/NeoHubR/releases).
2. Drag `NeoHubR.app` into `/Applications`.
3. **First-run Note**: Since this build is not notarized, if macOS blocks it, just **Right-click -> Open** in Finder, or allow it via System Settings -> Privacy & Security.

## 💡 How to Play

### Command Line (CLI)

Use `nh` instead of `neovide` in your terminal. It handles de-duplication and brings existing windows to the front automatically.

### Hotkeys (Default)

* `⌃ + \``: Summon the Project Switcher.
* `⌘ ⌃ Z`: Quickly jump back to the last active editor.
* **Inside the Switcher**:
* `⇥ (Tab)` / `shift + ⇥ (Tab)`: Cycle through editors.
* `⌘ Q`: Quit all editors.
* `⌘ ⌫`: Quit the selected editor.



> [!TIP]
> Most shortcuts can be customized in the Settings. More customization options are coming soon!

## 🏗️ Build from Source

```bash
open NeoHubR.xcodeproj
# Build the App and CLI separately
xcodebuild -project NeoHubR.xcodeproj -scheme NeoHubR -configuration Debug build
xcodebuild -project NeoHubR.xcodeproj -scheme NeoHubRCLI -configuration Debug build

```

## 🧭 Roadmap (Short)

### Latest Release (v0.3.4)
- **Architecture Overhaul**: Native Swift Concurrency (`async/await`) adoption for improved performance and thread safety.
- **Modern CLI**: Completely rewritten `nh` tool with native path resolution and robust IPC.
- **Enhanced Security**: User-isolated socket paths for better multi-user support.
- **UI Refinement**: Optimized project editor, icons, and smoother switcher interactions.

### Next
- **v0.4.0**: Manual project add (folder / Session.vim); Session labeling; project editor (path/icon/color); per‑project icon & color with Switcher display.
- **v0.4.1**: Attach to running Neovide instances (hybrid strategy); GUI launch environment inheritance.
- **v0.5.0**: Switcher visuals & interaction polish; single‑file mode.

## 🤝 Credits

* App Icon: [u/danbee](https://www.reddit.com/user/danbee/)
* Original Inspiration: [alex35mil/NeoHub](https://github.com/alex35mil/NeoHub) (Forked, heavily refactored, and polished)

## 📄 License

This project is licensed under the **MIT License**.

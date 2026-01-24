# 🚀 NeoHubR

<p align="center">
<img width="757" height="418" alt="NeoHubR Demo" src="https://github.com/user-attachments/assets/724d0e7f-ca91-4759-9e15-5005f82038fc" />
</p>

<p align="center">
<strong>Give your Neovide "Superpowers" on macOS ⚡️</strong>
</p>

<p align="center">
<a href="README_CN.md">简体中文</a>
</p>

---

**NeoHubR** (**Reboot**) is a dedicated menu bar companion for **Neovide** on macOS. It’s designed to rescue you from window chaos, helping you manage multiple editor instances and teleport between projects with buttery-smooth hotkeys.

## 📸 Screenshots

<p align="center">
<img width="411" height="474" alt="NeoHubR Screenshot 1" src="https://github.com/user-attachments/assets/eaf9400f-1ee9-4522-9048-1039604c8a6e" />
<img width="411" height="474" alt="NeoHubR Screenshot 2" src="https://github.com/user-attachments/assets/8257b402-1d5d-4f86-9fdd-c509d59650cd" />
</p>

## ✨ Feature Highlights

* **🖱️ Menu Bar Workflow**: Instant access to all running editors with a single click.
* **⌨️ Seamless Switcher**: Summon a global switcher to "teleport" between different projects.
* **🚀 Smart Launch (CLI)**: Stop duplicating! Opening a project via CLI will automatically re-activate the existing instance if it’s already running.
* **📂 Project Registry**: Keep your workspace organized with Starred and Recent project lists integrated directly into the switcher.
* **🔄 Quick Restart**: A dedicated hotkey to restart your current editor instance instantly.
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

Use `neohubr` instead of `neovide` in your terminal. It handles de-duplication and brings existing windows to the front automatically.

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

### Latest Release (v0.3.1)
- Path normalization so `neohubr`, `neohubr .`, and `neohubr <file>` map to the same project.
- Persistent validity checks with visual invalid styling and “Not available” label.
- Red trash deletion in Projects list with two‑step confirmation.

### Next
- **v0.4.0**: Manual project add (folder / Session.vim); Session labeling; project editor (path/icon/color); per‑project icon & color with Switcher display.
- **v0.4.1**: Attach to running Neovide instances (hybrid strategy); GUI launch environment inheritance (default: inherit on Switcher launch; implementation to be finalized).
- **v0.5.0**: Switcher visuals & interaction polish; single‑file mode.

## 🤝 Credits

* App Icon: [u/danbee](https://www.reddit.com/user/danbee/)
* Original Inspiration: [alex35mil/NeoHub](https://github.com/alex35mil/NeoHub) (Forked, heavily refactored, and polished)

## 📄 License

This project is licensed under the **MIT License**.

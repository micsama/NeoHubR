# NeoHub

<p align="center">
    <img width="757" height="418" alt="NeoHub Demo" src="https://github.com/user-attachments/assets/724d0e7f-ca91-4759-9e15-5005f82038fc" />
</p>

> 简体中文: [README_CN.md](README_CN.md)

---

NeoHub (app name shown as **NeoHubR**) is a menu bar companion for **Neovide** on macOS.  
This README focuses on **user-visible features** first.

## Screenshots
<p>
  <img width="411" height="474" alt="NeoHub Screenshot 1" src="https://github.com/user-attachments/assets/eaf9400f-1ee9-4522-9048-1039604c8a6e" />
  <img width="411" height="474" alt="NeoHub Screenshot 2" src="https://github.com/user-attachments/assets/8257b402-1d5d-4f86-9fdd-c509d59650cd" />
</p>

## Features (User-Facing)
- **Menu bar workflow**: instant access, editor list, and quick actions.
- **Editor switcher**: global hotkeys to summon and jump between editors.
- **Smart launch**: CLI de-duplicates by project path and re-activates existing instances.
- **Project registry**: Starred / Recent project lists integrated into switcher & settings.
- **Restart shortcuts**: restart current editor with a dedicated hotkey.
- **Notifications**: clear system notifications for CLI and editor lifecycle events.
- **Modern Settings**: native SwiftUI Settings scene with General / Projects / Advanced tabs.
- **Liquid Glass direction**: modern macOS visuals with fallbacks for older systems.

## Why NeoHub
Neovide is fantastic, but on macOS:
1. Multiple instances are hard to distinguish in `⌘⇥` because every process is just `neovide`.
2. Reopening an existing project often creates swap‑file conflicts.

## Requirements
- macOS 14+
- Neovide in your `PATH`
- CLI installed once (from Settings)

## Install
Download the latest `.dmg` from GitHub Releases (or build locally with Xcode).  
Open the DMG, drag `NeoHub.app` into `/Applications`, then launch it.  
On first run, install the CLI from Settings.

Note: This build is not notarized.  
If macOS blocks it, right‑click the app → Open, or allow it in System Settings → Privacy & Security.

## Usage
**CLI**  
Use `neohub` to launch editors. It de‑duplicates by project path and activates existing instances.

**App**
- `⌘⌃N` opens the switcher.
- `⌘⌃Z` activates the last editor.
- All shortcuts are configurable in Settings.
- Switcher supports `⌘Q` (quit all), `⌘⌫` (quit selected), and `⇥` (cycle).

## Build
```bash
open NeoHub.xcodeproj
xcodebuild -project NeoHub.xcodeproj -scheme NeoHub -configuration Debug build
xcodebuild -project NeoHub.xcodeproj -scheme NeoHubCLI -configuration Debug build
```

## Credits
- App icon: u/danbee
- Original project: alex35mil/NeoHub (forked and heavily refactored)

## License
MIT

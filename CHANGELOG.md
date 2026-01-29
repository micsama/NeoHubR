#  Changelog

## Unreleased
- Avoid activation errors when the previous activation target is no longer running/visible.

## 0.3.5
- Attach to running Neovide instances (hybrid strategy).
- Switcher data flow cleanup (items cache + refreshData) and stability improvements.
- CLI install modernization: `nh` path sync + legacy `neohub` symlink.
- Project list deletion reliability fix by stabilizing ID matching.

## 0.3.4
- Security hardening: socket path is user-isolated and path handling is unified.
- Readme/roadmap refresh for the Reboot era.

## 0.3.3
- Restore running instances after restart from `/tmp/neohubr.instances.json`.
- Session.vim default name uses parent folder.
- Repository structure cleanup: App/Core/Support grouping and file moves.

## 0.3.2
- Add Project Editor with icon/color controls, preview, and session-aware editing.
- Support Session.vim projects (file-based entries) alongside folder projects.
- Rework Switcher list rendering (ScrollView/LazyVStack) with unified row styling and icon/color display.
- Update Projects settings: switcher item range 4–20 and a compact add menu for folder/session.
- Add notification permission request button in Advanced settings with deep link to system settings.
- Disable CLI coverage instrumentation to prevent `default.profraw` output.

## 0.2.1
- Add missing entitlement.

## 0.2.0
- Update to the current Neovide.
- Add hotkey to activate last used editor directly.
- Add hotkey to restart current editor.
- Use `⇥` to cycle through the editors in the switcher.
- Fix installation script.

## 0.1.1
- Fix CLI version.

## 0.1.0
- Sort editors:
    - in menubar: by name
    - in switcher: by access time
- Fix a few edge cases in the apps activation logic.

## 0.0.1
Initial release.

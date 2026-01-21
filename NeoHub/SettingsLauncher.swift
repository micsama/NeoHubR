import AppKit

@MainActor
enum SettingsLauncher {
    static func open() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

import AppKit
import Foundation

enum MainThread {
    static func assert() {
        #if DEBUG
            dispatchPrecondition(condition: .onQueue(.main))
        #endif
    }

    static func run(_ action: @MainActor @escaping () -> Void) {
        Task { @MainActor in action() }
    }

    static func after(_ delay: TimeInterval, _ action: @MainActor @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            Task { @MainActor in action() }
        }
    }
}

enum ActivationTarget {
    case neohubr(NonSwitcherWindow)
    case neovide(Editor)
    case other(NSRunningApplication)
}

@MainActor
struct NonSwitcherWindow {
    let window: NSWindow

    init?(_ window: NSWindow, switcherWindow: SwitcherWindowRef) {
        guard !switcherWindow.isSameWindow(window) else { return nil }
        self.window = window
    }

    func activate() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class ActivationManager {
    private(set) var activationTarget: ActivationTarget?

    public func setActivationTarget(
        currentApp: NSRunningApplication?,
        switcherWindow: SwitcherWindowRef,
        editors: [Editor]
    ) {
        let nextActivationTarget = currentApp.flatMap { app in
            if app.bundleIdentifier == APP_BUNDLE_ID {
                if let currentWindow = NSApplication.shared.mainWindow,
                    let nonSwitcherWindow = NonSwitcherWindow(currentWindow, switcherWindow: switcherWindow)
                {
                    return ActivationTarget.neohubr(nonSwitcherWindow)
                } else {
                    return nil
                }
            }

            if let editor = editors.first(where: { editor in editor.processIdentifier == app.processIdentifier }) {
                return .neovide(editor)
            }

            return .other(app)
        }

        self.activationTarget = nextActivationTarget
    }

    public func activateTarget() {
        guard let target = self.activationTarget else { return }

        switch target {
        case .neohubr(let window):
            guard window.window.isVisible else {
                self.activationTarget = nil
                return
            }
            window.activate()
        case .neovide(let editor):
            guard let app = NSRunningApplication(processIdentifier: editor.processIdentifier),
                !app.isTerminated
            else {
                self.activationTarget = nil
                return
            }
            editor.activate()
        case .other(let app):
            guard !app.isTerminated else {
                self.activationTarget = nil
                return
            }
            app.activate()
        }
    }
}

import AppKit
import Foundation
import NeoHubRLib

// MARK: - Logger

private let defaultLevel: LogLevel = {
    #if DEBUG
        return .debug
    #else
        return .info
    #endif
}()

let log = Logger.bootstrap(subsystem: APP_BUNDLE_ID, category: "app", defaultLevel: defaultLevel)

// MARK: - ProjectPathFormatter

enum ProjectPathFormatter {
    static func displayPath(_ url: URL) -> String {
        displayPath(url.path(percentEncoded: false))
    }

    static func displayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let lowerPath = path.lowercased()
        let lowerHome = home.lowercased()
        if lowerPath == lowerHome {
            return "~"
        }
        if lowerPath.hasPrefix(lowerHome + "/") {
            let suffix = path.dropFirst(home.count)
            return "~" + suffix
        }
        return path
    }

    static func expandTilde(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}

// MARK: - NeovideResolver

enum NeovideResolver {
    static func resolveBinary() -> URL? {
        if let path = resolveFromPath() {
            return path
        }

        let bundled = URL(fileURLWithPath: "/Applications/Neovide.app/Contents/MacOS/neovide")
        if FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }

        return nil
    }

    private static func resolveFromPath() -> URL? {

        let process = Process()

        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")

        process.arguments = ["which", "neovide"]

        process.standardOutput = pipe

        do {

            try process.run()

            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()

            guard

                let path = String(data: data, encoding: .utf8)?

                    .trimmingCharacters(in: .whitespacesAndNewlines),

                !path.isEmpty

            else { return nil }

            return URL(fileURLWithPath: path)

        } catch {

            return nil

        }

    }

}

// MARK: - Activation Logic

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


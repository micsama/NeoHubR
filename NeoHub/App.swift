import AppKit
import KeyboardShortcuts
import NeoHubLib
import SwiftUI

let APP_NAME = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as! String
let APP_VERSION = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
let APP_BUILD = Bundle.main.object(forInfoDictionaryKey: "GitCommitHash") as! String
let APP_BUNDLE_ID = Bundle.main.bundleIdentifier!

extension KeyboardShortcuts.Name {
    static let toggleSwitcher = Self(
        "toggleSwitcher",
        default: .init(.n, modifiers: [.command, .control])
    )

    static let toggleLastActiveEditor = Self(
        "toggleLastActiveEditor",
        default: .init(.z, modifiers: [.command, .control])
    )

    static let restartEditor = Self("restartEditor")
}

@main
struct NeoHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var app

    var body: some Scene {
        MenuBarExtra(
            content: {
                MenuBarView(
                    cli: app.cli,
                    editorStore: app.editorStore
                )
            },
            label: { MenuBarIcon() }
        )
        Settings {
            SettingsView(
                cli: app.cli,
                appSettings: app.appSettings,
                projectRegistry: app.projectRegistry
            )
        }

        Window("About", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        // TODO(macOS 15+): Consider enabling WindowDragGesture for background drag.
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let cli: CLI
    let editorStore: EditorStore
    let server: SocketServer
    let switcherWindow: SwitcherWindow
    let activationManager: ActivationManager
    let appSettings: AppSettingsStore
    let projectRegistry: ProjectRegistryStore

    override init() {
        let appSettings = AppSettingsStore()
        self.appSettings = appSettings

        let cli = CLI()
        let activationManager = ActivationManager()
        let projectRegistry = ProjectRegistryStore()

        let switcherWindowRef = SwitcherWindowRef()

        let editorStore = EditorStore(
            activationManager: activationManager,
            switcherWindow: switcherWindowRef,
            projectRegistry: projectRegistry
        )

        self.cli = cli
        self.server = SocketServer(store: editorStore)
        self.editorStore = editorStore
        self.switcherWindow = SwitcherWindow(
            editorStore: editorStore,
            selfRef: switcherWindowRef,
            activationManager: activationManager,
            appSettings: appSettings,
            projectRegistry: projectRegistry
        )
        self.activationManager = activationManager
        self.projectRegistry = projectRegistry

        switcherWindowRef.set(self.switcherWindow)

        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationManager.shared.registerDelegate()

        self.server.start()

        Task { @MainActor in
            let status = await self.cli.refreshStatus()
            if case .error(_) = status {
                self.showCLIAlert(status)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        switcherWindow.hide()
    }

    func applicationWillTerminate(_ notification: Notification) {
        server.stop()
    }

    private func showCLIAlert(_ status: CLIStatus) {
        guard case .error(let reason) = status else { return }

        let alert = NSAlert()
        switch reason {
        case .notInstalled:
            alert.messageText = String(localized: "NeoHub CLI is not installed")
            alert.informativeText = String(localized: "Please open Settings to install the CLI.")
        case .versionMismatch:
            alert.messageText = String(localized: "NeoHub CLI needs to be updated")
            alert.informativeText = String(localized: "Please open Settings to update the CLI.")
        case .unexpectedError:
            alert.messageText = String(localized: "NeoHub CLI error")
            alert.informativeText = String(localized: "Please open Settings and check logs.")
        }

        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Open Settings"))
        alert.runModal()
    }
}

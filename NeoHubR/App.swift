import AppKit
import KeyboardShortcuts
import NeoHubRLib
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
struct NeoHubRApp: App {
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
        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsLink {
                    Text("Settings…")
                }
            }
        }
        Settings {
            SettingsView(
                cli: app.cli,
                appSettings: app.appSettings,
                projectRegistry: app.projectRegistry
            )
        }

        WindowGroup("Project Editor", id: "project-editor", for: URL.self) { value in
            if let projectID = value.wrappedValue {
                ProjectEditorView(
                    projectID: projectID,
                    projectRegistry: app.projectRegistry
                )
            }
        }
        .windowResizability(.contentSize)
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
        self.projectRegistry.refreshValidity()

        Task { @MainActor in
            let status = await self.cli.refreshStatus()
            if case .error(let reason) = status {
                switch reason {
                case .notInstalled:
                    NotificationManager.sendInfo(
                        title: String(localized: "NeoHubR CLI is not installed"),
                        body: String(localized: "Please open Settings to install the CLI.")
                    )
                case .versionMismatch:
                    NotificationManager.sendInfo(
                        title: String(localized: "NeoHubR CLI needs to be updated"),
                        body: String(localized: "Please open Settings to update the CLI.")
                    )
                case .unexpectedError(let err):
                    let error = ReportableError("CLI unexpected error", error: err)
                    NotificationManager.send(kind: .cliUnexpectedError, error: error)
                }
            }
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        switcherWindow.hide()
    }

    func applicationWillTerminate(_ notification: Notification) {
        server.stop()
    }

    // CLI error alert handled in MenuBarView using SwiftUI + openSettings.
}

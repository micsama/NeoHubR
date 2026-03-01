import AppKit
import KeyboardShortcuts
import NeoHubRLib
import ServiceManagement
import Darwin
import SwiftUI

let APP_NAME = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as! String
let APP_VERSION = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
let APP_BUILD = Bundle.main.object(forInfoDictionaryKey: "GitCommitHash") as! String
let APP_BUNDLE_ID = Bundle.main.bundleIdentifier!

extension KeyboardShortcuts.Name {
    static let toggleSwitcher = Self(
        "toggleSwitcher",
        default: .init(.backtick, modifiers: [.control])
    )

    static let toggleLastActiveEditor = Self(
        "toggleLastActiveEditor",
        default: .init(.z, modifiers: [.command, .control])
    )
}

@main
struct NeoHubRApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var app

    var body: some Scene {
        MenuBarExtra(
            content: {
                MenuBarView(
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
    let switcherWindow: SwitcherWindow
    let activationManager: ActivationManager
    let appSettings: AppSettingsStore
    let projectRegistry: ProjectRegistryStore

    override init() {
        disableProfilingOutput()
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

        self.projectRegistry.refreshValidity()
        self.editorStore.restoreActiveEditors()

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
    }

    // CLI error alert handled in MenuBarView using SwiftUI + openSettings.
}

@inline(__always)
private func disableProfilingOutput() {
    setenv("LLVM_PROFILE_FILE", "/dev/null", 1)
}

@MainActor
extension AppSettingsStore {
    var launchAtLogin: Bool {
        get {
            let status = SMAppService.mainApp.status
            return status == .enabled || status == .requiresApproval
        }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                log.error("Failed to toggle launch at login: \(error)")
            }
        }
    }
}

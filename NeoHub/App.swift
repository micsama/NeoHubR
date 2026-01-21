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
                    editorStore: app.editorStore,
                    aboutWindow: app.aboutWindow
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
        .defaultSize(width: SettingsView.defaultWidth, height: SettingsView.defaultHeight)
        .windowResizability(.contentSize)
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let cli: CLI
    let editorStore: EditorStore
    let server: SocketServer
    let switcherWindow: SwitcherWindow
    let installationWindow: RegularWindow<InstallationView>
    let aboutWindow: RegularWindow<AboutView>
    let settingsWindow: RegularWindow<SettingsView>
    let windowCounter: WindowCounter
    let activationManager: ActivationManager
    let appSettings: AppSettingsStore
    let projectRegistry: ProjectRegistryStore

    override init() {
        let appSettings = AppSettingsStore()
        self.appSettings = appSettings

        let cli = CLI()
        let windowCounter = WindowCounter()
        let activationManager = ActivationManager()
        let projectRegistry = ProjectRegistryStore()

        let switcherWindowRef = SwitcherWindowRef()
        let installationWindowRef = RegularWindowRef<InstallationView>()

        let editorStore = EditorStore(
            activationManager: activationManager,
            switcherWindow: switcherWindowRef,
            projectRegistry: projectRegistry
        )

        self.cli = cli
        self.server = SocketServer(store: editorStore)
        self.editorStore = editorStore
        self.aboutWindow = RegularWindow(
            width: AboutView.defaultWidth,
            content: { AboutView() },
            windowCounter: windowCounter
        )
        self.settingsWindow = RegularWindow(
            width: SettingsView.defaultWidth,
            content: {
                SettingsView(
                    cli: cli,
                    appSettings: appSettings,
                    projectRegistry: projectRegistry
                )
            },
            windowCounter: windowCounter
        )
        self.switcherWindow = SwitcherWindow(
            editorStore: editorStore,
            settingsWindow: self.settingsWindow,
            selfRef: switcherWindowRef,
            activationManager: activationManager,
            appSettings: appSettings,
            projectRegistry: projectRegistry
        )
        self.windowCounter = windowCounter
        self.activationManager = activationManager
        self.projectRegistry = projectRegistry

        self.installationWindow = RegularWindow(
            title: APP_NAME,
            width: InstallationView.defaultWidth,
            content: {
                InstallationView(
                    cli: cli,
                    installationWindow: installationWindowRef
                )
            },
            windowCounter: windowCounter
        )

        switcherWindowRef.set(self.switcherWindow)
        installationWindowRef.set(self.installationWindow)

        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationManager.shared.registerDelegate()

        self.server.start()

        Task { @MainActor in
            let status = await self.cli.refreshStatus()
            if case .error(_) = status {
                self.installationWindow.open()
            }
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        switcherWindow.hide()
    }

    func applicationWillTerminate(_ notification: Notification) {
        server.stop()
    }
}

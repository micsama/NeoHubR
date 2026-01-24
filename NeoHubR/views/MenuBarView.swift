import NeoHubRLib
import Observation
import SwiftUI

struct MenuBarIcon: View {
    private let icon: NSImage

    init() {
        let icon: NSImage = NSImage(named: "MenuBarIcon")!
        icon.isTemplate = true
        self.icon = icon
    }

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .scaledToFit()
            .frame(width: 15, height: 15)
    }
}

struct MenuBarView: View {
    @Bindable var cli: CLI
    @Bindable var editorStore: EditorStore

    var body: some View {
        let editors = editorStore.getEditors(sortedFor: .menubar)

        Group {
            if editors.isEmpty {
                Text("No editors").font(.headline)
            } else {
                Text("Editors").font(.headline)
                ForEach(editors) { editor in
                    Button(editor.name) { editor.activate() }
                }
            }
            switch cli.status {
            case .error(reason: .notInstalled), .error(reason: .versionMismatch):
                Divider()
                Text("CLI Action Required")
                    .font(.headline)
                let titleKey: LocalizedStringKey = {
                    switch cli.status {
                    case .error(reason: .versionMismatch):
                        return "Update CLI"
                    default:
                        return "Install CLI"
                    }
                }()
                Button {
                    Task { @MainActor in
                        let response = await cli.run(.install)
                        Self.showCLIInstallationAlert(with: response)
                    }
                } label: {
                    Label(titleKey, systemImage: "exclamationmark.triangle.fill")
                }
            case .error(reason: .unexpectedError(_)):
                Divider()
                SettingsLink { Label("CLI Error", systemImage: "exclamationmark.triangle.fill") }
                    .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
            case .ok:
                EmptyView()
            }
            Divider()
            SettingsLink { Label("Settings…", systemImage: "gearshape") }
                // MenuBarExtra opens Settings without focus in accessory apps; activate to ensure key window.
                .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
                .keyboardShortcut(",", modifiers: .command)
            Divider()
            Button("Quit All Editors") { Task { await editorStore.quitAllEditors() } }
                .disabled(editors.isEmpty)
            Button(String(localized: "Quit NeoHubR")) { NSApplication.shared.terminate(nil) }
        }
    }
    @MainActor
    static func showCLIInstallationAlert(with response: (result: Result<Void, CLIInstallationError>, status: CLIStatus))
    {
        switch response.result {
        case .success(()):
            NotificationManager.sendInfo(
                title: String(localized: "Boom!"),
                body: String(localized: "The CLI is ready to roll 🚀")
            )

        case .failure(.userCanceledOperation): ()

        case .failure(let error):
            let alert = NSAlert()
            alert.messageText = String(localized: "Oh no!")
            alert.alertStyle = .critical
            alert.addButton(withTitle: String(localized: "Report"))
            alert.addButton(withTitle: String(localized: "Dismiss"))

            let reportError: ReportableError
            switch error {
            case .failedToCreateAppleScript:
                alert.informativeText = String(localized: "There was an issue during installation.")
                reportError = ReportableError("Failed to build installation Apple Script")
            case .failedToExecuteAppleScript(let message):
                alert.informativeText = message
                reportError = ReportableError(
                    "Failed to execute installation Apple Script",
                    meta: ["AppleScriptError": message]
                )
            case .userCanceledOperation:
                return
            }

            switch alert.runModal() {
            case .alertFirstButtonReturn:
                BugReporter.report(reportError)
            default: ()
            }
        }
    }

}

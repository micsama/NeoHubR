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
    @ObservedObject var cli: CLI
    @ObservedObject var editorStore: EditorStore

    let aboutWindow: RegularWindow<AboutView>

    var body: some View {
        let editors = editorStore.getEditors(sortedFor: .menubar)

        Group {
            if editors.count == 0 {
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
                let title: String = {
                    switch cli.status {
                    case .error(reason: .versionMismatch):
                        return "⚠️ Update CLI"
                    default:
                        return "⚠️ Install CLI"
                    }
                }()
                Button(title) {
                    Task { @MainActor in
                        let response = await cli.run(.install)
                        Self.showCLIInstallationAlert(with: response)
                    }
                }
            case .error(reason: .unexpectedError(_)):
                Divider()
                SettingsLink { Text("❗ CLI Error") }
                    .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
            case .ok:
                EmptyView()
            }
            Divider()
            SettingsLink { Text("Settings") }
                // MenuBarExtra opens Settings without focus in accessory apps; activate to ensure key window.
                .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
            Button("About") { aboutWindow.open() }
            Divider()
            Button("Quit All Editors") { Task { await editorStore.quitAllEditors() } }
                .disabled(editors.count == 0)
            Button("Quit NeoHub") { NSApplication.shared.terminate(nil) }
        }
    }

    @MainActor
    static func showCLIInstallationAlert(with response: (result: Result<Void, CLIInstallationError>, status: CLIStatus)) {
        switch response.result {
        case .success(()):
            let alert = NSAlert()

            alert.messageText = String(localized: "Boom!")
            alert.informativeText = String(localized: "The CLI is ready to roll 🚀")
            alert.alertStyle = .informational
            alert.addButton(withTitle: String(localized: "OK"))

            alert.runModal()

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
            case .failedToExecuteAppleScript(message: let message):
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

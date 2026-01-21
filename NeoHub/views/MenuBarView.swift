import SwiftUI

struct MenuBarIcon: View {
    private let icon: NSImage

    init() {
        let icon: NSImage = NSImage(named: "MenuBarIcon")!

        let ratio = icon.size.height / icon.size.width
        icon.size.height = 15
        icon.size.width = 15 / ratio

        self.icon = icon
    }

    var body: some View {
        Image(nsImage: icon)
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
            case .error(reason: .notInstalled):
                Divider()
                Button("⚠️ Install CLI") {
                    Task { @MainActor in
                        let response = await cli.run(.install)
                        Self.showCLIInstallationAlert(with: response)
                    }
                }
            case .error(reason: .versionMismatch):
                Divider()
                Button("⚠️ Update CLI") {
                    Task { @MainActor in
                        let response = await cli.run(.install)
                        Self.showCLIInstallationAlert(with: response)
                    }
                }
            case .error(reason: .unexpectedError(_)):
                Divider()
                Button("❗ CLI Error") { SettingsLauncher.open() }
            case .ok:
                EmptyView()
            }
            Divider()
            SettingsLink { Text("Settings") }
            Button("About") { aboutWindow.open() }
            Divider()
            Button("Quit All Editors") { Task { await editorStore.quitAllEditors() } }.disabled(editors.count == 0)
            Button("Quit NeoHub") { NSApplication.shared.terminate(nil) }
        }
    }

    @MainActor
    static func showCLIInstallationAlert(with response: (result: Result<Void, CLIInstallationError>, status: CLIStatus))
    {
        switch response.result {
        case .success(()):
            let alert = NSAlert()

            alert.messageText = "Boom!"
            alert.informativeText = "The CLI is ready to roll 🚀"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")

            alert.runModal()

        case .failure(.userCanceledOperation): ()

        case .failure(.failedToCreateAppleScript):
            let alert = NSAlert()

            alert.messageText = "Oh no!"
            alert.informativeText = "There was an issue during installation."
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Report")
            alert.addButton(withTitle: "Dismiss")

            switch alert.runModal() {
            case .alertFirstButtonReturn:
                let error = ReportableError("Failed to build installation Apple Script")
                BugReporter.report(error)
            default: ()
            }

        case .failure(.failedToExecuteAppleScript(error: let error)):
            let alert = NSAlert()

            alert.messageText = "Oh no!"
            alert.informativeText = "There was an issue during installation."
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Report")
            alert.addButton(withTitle: "Dismiss")

            switch alert.runModal() {
            case .alertFirstButtonReturn:
                let error = ReportableError(
                    "Failed to execute installation Apple Script",
                    meta: error.mapValues { $0 as Any }
                )
                BugReporter.report(error)
            default: ()
            }
        }
    }
}

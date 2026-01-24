import Observation
import SwiftUI

struct MenuBarIcon: View {
    var body: some View {
        Image("MenuBarIcon")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 15, height: 15)
    }
}

struct MenuBarView: View {
    @Bindable var cli: CLI
    @Bindable var editorStore: EditorStore

    private var cliStatusHint: LocalizedStringKey? {
        switch cli.status {
        case .ok:
            return "CLI Hint Open"
        case .error(reason: .notInstalled):
            return "CLI Hint Install"
        case .error(reason: .versionMismatch):
            return "CLI Hint Update"
        case .error(reason: .unexpectedError):
            return "CLI Hint Error"
        }
    }
    
    var body: some View {
        let editors = editorStore.getEditors(sortedFor: .menubar)

        Section("Editors") {
            if editors.isEmpty {
                Text("No editors")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(editors) { editor in
                    Button(editor.name) { editor.activate() }
                }
            }
        }

        Section {
            if let cliStatusHint {
                Label(cliStatusHint, systemImage: "arrow.down")
                    .foregroundStyle(.secondary)
            }
            SettingsLink { Label("Settings…", systemImage: "gearshape") }
                // MenuBarExtra opens Settings without focus in accessory apps; activate to ensure key window.
                .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
        }

        Section {
            Button("Quit All Editors") { Task { await editorStore.quitAllEditors() } }
                .disabled(editors.isEmpty)
            Button(String(localized: "Quit NeoHubR")) { NSApplication.shared.terminate(nil) }
        }
    }
}

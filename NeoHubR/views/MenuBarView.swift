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
            SettingsLink { Label("Settings…", systemImage: "gearshape") }
        }

        Section {
            Button("Quit All Editors") { Task { await editorStore.quitAllEditors() } }
                .disabled(editors.isEmpty)
            Button(String(localized: "Quit NeoHubR")) { NSApplication.shared.terminate(nil) }
        }
    }
}

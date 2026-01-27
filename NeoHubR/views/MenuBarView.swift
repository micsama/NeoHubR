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
    @Bindable var editorStore: EditorStore

    var body: some View {
        let editors = editorStore.getEditors(sortedFor: .menubar)

        Section("Editors") {
            if editors.isEmpty {
                Text("No editors")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(editors) { editor in
                    Button {
                        editor.activate()
                    } label: {
                        Label(editor.name, systemImage: "terminal")
                    }
                }
            }
        }

        Divider()

        SettingsLink {
            Label("Settings…", systemImage: "gearshape")
        }

        Section {
            Button {
                Task { await editorStore.quitAllEditors() }
            } label: {
                Label("Quit All Editors", systemImage: "xmark.circle")
            }
            .disabled(editors.isEmpty)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label(String(localized: "Quit NeoHubR"), systemImage: "power")
            }
        }
    }
}

import AppKit
import NeoHubRLib
import SwiftUI
import UniformTypeIdentifiers

struct ProjectEditorView: View {
    let projectID: URL
    @Bindable var projectRegistry: ProjectRegistryStore

    @Environment(\.dismiss) private var dismiss

    @State private var loadedEntry: ProjectEntry?
    @State private var state = EditorState()
    @State private var isIconPickerPresented = false

    var body: some View {
        VStack(spacing: 12) {
            previewCard
            editorFields
            actionsBar
        }
        .padding(16)
        .frame(width: 255, height: 350)
        .task { loadInitialData() }
    }

    private var editorFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            nameField
            projectField
            if loadedEntry?.isSession == true {
                sessionField
            }
            iconField
            colorField
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Project Name")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Project Name", text: $state.name)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var projectField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Project Path")
                .foregroundStyle(state.isProjectPathValid ? Color.primary : Color.red)
                .font(.caption)
                .fontWeight(state.isProjectPathValid ? .regular : .bold)
            PathField(
                path: $state.projectPath,
                allowedTypes: [.folder],
                expectsDirectory: true
            )
        }
    }

    private var sessionField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Session.vim Path")
                .font(.caption)
                .foregroundStyle(.secondary)
            PathField(
                path: $state.sessionPath,
                allowedTypes: [.data],
                expectsDirectory: false
            )
        }
    }

    @ViewBuilder
    private var iconField: some View {
        let emojiTooLong = state.emojiValue.count > 2
        let emojiBorder: Color = {
            if emojiTooLong { return .red }
            return state.iconMode == .emoji ? .accentColor : .clear
        }()

        VStack(alignment: .leading, spacing: 6) {
            Text("Icon")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                if state.iconMode == .default {
                    Button(String(localized: "Default")) {
                        state.iconMode = .default
                        state.symbolName = "folder.fill"
                        state.emojiValue = ""
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(String(localized: "Default")) {
                        state.iconMode = .default
                        state.symbolName = "folder.fill"
                        state.emojiValue = ""
                    }
                    .buttonStyle(.bordered)
                }

                if state.iconMode == .symbol {
                Button {
                    state.iconMode = .symbol
                    isIconPickerPresented = true
                } label: {
                    Image(systemName: "square.grid.2x2")
                }
                    .buttonStyle(.borderedProminent)
                    .popover(isPresented: $isIconPickerPresented, arrowEdge: .bottom) {
                        iconPickerPopover
                    }
                } else {
                    Button {
                        state.iconMode = .symbol
                        isIconPickerPresented = true
                    } label: {
                        Image(systemName: "square.grid.2x2")
                    }
                    .buttonStyle(.bordered)
                    .popover(isPresented: $isIconPickerPresented, arrowEdge: .bottom) {
                        iconPickerPopover
                    }
                }

                TextField(String(localized: "Emoji / Character"), text: $state.emojiValue)
                    .textFieldStyle(.roundedBorder)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(emojiBorder, lineWidth: 1)
                    )
                    .frame(maxWidth: .infinity)
                    .onChange(of: state.emojiValue) { _, newValue in
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        if isValidSymbolName(trimmed) {
                            state.iconMode = .symbol
                            state.symbolName = trimmed
                        } else {
                            state.iconMode = .emoji
                        }
                    }
            }
        }
    }

    private var colorField: some View {
        let presets = EditorState.colorPresets
        let palette: [(color: Color?, presetIndex: Int?)] = [
            (color: nil, presetIndex: nil)
        ] + presets.enumerated().map { (color: $0.element, presetIndex: $0.offset) }
        let firstRow = palette.prefix(6)
        let secondRow = palette.dropFirst(6).prefix(6)

        return VStack(alignment: .leading, spacing: 6) {
            Text("Color")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(Array(firstRow.enumerated()), id: \.offset) { _, item in
                            ColorSwatch(
                                color: item.color,
                                isSelected: item.presetIndex == nil
                                    ? !state.useCustomColor
                                    : state.useCustomColor && state.selectedPresetIndex == item.presetIndex
                            ) {
                                if let presetIndex = item.presetIndex, let color = item.color {
                                    state.selectPresetColor(color, index: presetIndex)
                                } else {
                                    state.selectNoneColor()
                                }
                            }
                        }
                    }

                    HStack(spacing: 6) {
                        ForEach(Array(secondRow.enumerated()), id: \.offset) { _, item in
                            ColorSwatch(
                                color: item.color,
                                isSelected: item.presetIndex == nil
                                    ? !state.useCustomColor
                                    : state.useCustomColor && state.selectedPresetIndex == item.presetIndex
                            ) {
                                if let presetIndex = item.presetIndex, let color = item.color {
                                    state.selectPresetColor(color, index: presetIndex)
                                } else {
                                    state.selectNoneColor()
                                }
                            }
                        }
                    }
                }
                .frame(width: 140, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "paintpalette")
                            .foregroundStyle(.secondary)
                        Text(String(localized: "Custom"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    ColorPicker(String(localized: "Choose Color"), selection: $state.color, supportsOpacity: false)
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onTapGesture {
                            state.selectCustomColor(state.color)
                        }
                        .onChange(of: state.color) { _, newValue in
                            state.selectCustomColor(newValue)
                        }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var actionsBar: some View {
        HStack {
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.escape, modifiers: [])
                .frame(maxWidth: .infinity)
            Button("Save") { save() }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!state.canSave)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var previewCard: some View {
        let trimmedName = state.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedURL = state.normalizedProjectURL ?? loadedEntry?.id
        let emojiText = state.emojiValue.isEmpty ? "🙂" : state.emojiValue
        let emojiFontSize: CGFloat = emojiText.count > 1 ? 20 : 28
        let displayName: String = {
            if !trimmedName.isEmpty {
                return trimmedName
            }
            if let entryName = loadedEntry?.name, !entryName.isEmpty {
                return entryName
            }
            if let resolvedURL {
                return resolvedURL.lastPathComponent
            }
            return String(localized: "Untitled")
        }()

        let displayPath: String = {
            if let resolvedURL {
                return ProjectPathFormatter.displayPath(resolvedURL)
            }
            return "-"
        }()

        let iconColor = state.useCustomColor ? state.color : Color.secondary

        let card = HStack(spacing: 12) {
            Group {
                switch state.iconMode {
                case .default:
                    Image(systemName: "folder.fill")
                case .symbol:
                    Image(systemName: state.symbolName)
                case .emoji:
                    Text(emojiText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .allowsTightening(true)
                }
            }
            .font(.system(size: state.iconMode == .emoji ? emojiFontSize : 28))
            .foregroundStyle(iconColor)
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.headline)
                Text(displayPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(12)

        if #available(macOS 26.0, *) {
            card.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            card.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var iconPickerPopover: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(32), spacing: 8), count: 6),
            spacing: 8
        ) {
            ForEach(iconOptions, id: \.self) { symbol in
                Button {
                    state.iconMode = .symbol
                    state.symbolName = symbol
                } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 16))
                        .frame(width: 28, height: 24)
                        .foregroundStyle(.primary)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(
                                    state.iconMode == .symbol && state.symbolName == symbol
                                        ? Color.accentColor.opacity(0.18)
                                        : Color.clear
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: 240)
    }

    private var iconOptions: [String] {
        [
            "folder", "terminal", "doc.text", "tray", "cube", "memorychip",
            "gearshape", "wrench.and.screwdriver", "hammer", "bolt", "sparkles",
            "tag", "bookmark", "link", "paperplane", "star", "heart", "flame",
            "leaf", "globe", "briefcase", "camera", "paintbrush", "chart.bar",
            "map", "music.note", "gamecontroller", "graduationcap"
        ]
    }

    private func isValidSymbolName(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

}

// MARK: - Actions

private extension ProjectEditorView {
    func loadInitialData() {
        guard let entry = projectRegistry.entry(for: projectID) else { return }
        loadedEntry = entry
        state = EditorState(entry: entry)
    }

    func save() {
        guard let entry = loadedEntry,
              let updated = state.buildEntry(from: entry)
        else { return }
        projectRegistry.updateEntry(updated, replacing: entry.id)
        dismiss()
    }
}

// MARK: - PathField Component

private struct PathField: View {
    @Binding var path: String
    let allowedTypes: [UTType]
    let expectsDirectory: Bool

    @State private var isPickerPresented = false

    var body: some View {
        HStack(spacing: 8) {
            TextField("", text: $path)
                .textFieldStyle(.roundedBorder)
                .dropDestination(for: URL.self) { urls, _ in
                    handleDrop(urls)
                }

            Button("Browse") { isPickerPresented = true }
                .fileImporter(
                    isPresented: $isPickerPresented,
                    allowedContentTypes: allowedTypes
                ) { result in
                    if case .success(let url) = result {
                        path = url.path(percentEncoded: false)
                    }
                }
        }
    }

    private func handleDrop(_ urls: [URL]) -> Bool {
        guard let url = urls.first else { return false }

        if expectsDirectory {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                  isDir.boolValue
            else { return false }
        }

        path = url.path(percentEncoded: false)
        return true
    }
}

// MARK: - IconMode

private enum IconMode {
    case `default`, symbol, emoji
}

// MARK: - ColorSwatch

private struct ColorSwatch: View {
    let color: Color?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if let color {
                    Circle()
                        .fill(color)
                } else {
                    Circle()
                        .fill(Color.secondary.opacity(0.12))
                }
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1)

                if color == nil {
                    Image(systemName: "circle.slash")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 18, height: 18)
            .overlay(
                Circle()
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - EditorState

private struct EditorState {
    static let colorPresets: [Color] = [
        .black,
        .white,
        .red,
        .orange,
        .yellow,
        .green,
        .mint,
        .teal,
        .blue,
        .indigo,
        .purple
    ]

    var name = ""
    var projectPath = ""
    var sessionPath = ""
    var iconMode: IconMode = .default
    var symbolName = "folder.fill"
    var emojiValue = ""
    var useCustomColor = false
    var color: Color = .orange
    var selectedPresetIndex: Int?

    init() {}

    init(entry: ProjectEntry) {
        name = entry.name ?? ""
        projectPath = ProjectPathFormatter.displayPath(entry.id)
        sessionPath = entry.sessionPath.map { ProjectPathFormatter.displayPath($0) } ?? ""

        if let customColor = entry.customColor {
            useCustomColor = true
            color = customColor
            let hex = customColor.hexString()
            selectedPresetIndex = Self.colorPresets.firstIndex { $0.hexString() == hex }
        }

        if let icon = entry.iconDescriptor {
            switch icon.kind {
            case .symbol:
                iconMode = .symbol
                symbolName = icon.value
            case .emoji:
                iconMode = .emoji
                emojiValue = icon.value
            }
        }
    }

    var canSave: Bool { normalizedProjectURL != nil }

    var isProjectPathValid: Bool {
        guard let url = normalizedProjectURL else { return false }
        return ProjectRegistry.isAccessible(url)
    }

    mutating func selectNoneColor() {
        useCustomColor = false
        selectedPresetIndex = nil
    }

    mutating func selectPresetColor(_ preset: Color, index: Int) {
        useCustomColor = true
        selectedPresetIndex = index
        color = preset
    }

    mutating func selectCustomColor(_ newColor: Color) {
        useCustomColor = true
        selectedPresetIndex = nil
        color = newColor
    }

    func buildEntry(from entry: ProjectEntry) -> ProjectEntry? {
        guard let projectURL = normalizedProjectURL else { return nil }

        let sessionURL = buildSessionURL(for: entry)
        let iconValue = buildIconValue()
        let nameValue = buildName(projectURL: projectURL)
        let isValid = ProjectRegistry.isAccessible(projectURL)

        return ProjectEntry(
            id: projectURL,
            name: nameValue,
            icon: iconValue,
            colorHex: useCustomColor ? color.hexString() : nil,
            sessionPath: sessionURL,
            validity: isValid ? .valid : .invalid,
            lastCheckedAt: Date()
        )
    }

    var normalizedProjectURL: URL? {
        let trimmed = projectPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let expanded = ProjectPathFormatter.expandTilde(trimmed)
        return ProjectRegistry.normalizeID(URL(fileURLWithPath: expanded))
    }

    private func buildSessionURL(for entry: ProjectEntry) -> URL? {
        let trimmed = sessionPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard entry.isSession, !trimmed.isEmpty else { return nil }
        let expanded = ProjectPathFormatter.expandTilde(trimmed)
        return ProjectRegistry.normalizeSessionPath(URL(fileURLWithPath: expanded))
    }

    private func buildIconValue() -> String? {
        switch iconMode {
        case .default:
            return nil
        case .symbol:
            let trimmed = symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : "symbol:\(trimmed)"
        case .emoji:
            let trimmed = emojiValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : "emoji:\(trimmed)"
        }
    }

    private func buildName(projectURL: URL) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed == projectURL.lastPathComponent ? nil : trimmed
    }
}

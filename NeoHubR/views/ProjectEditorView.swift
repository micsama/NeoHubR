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
            if state.isSession {
                sessionField
            } else {
                projectField
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
            Text("Session (.vim) Path")
                .font(.caption)
                .foregroundStyle(.secondary)
            PathField(
                path: $state.sessionPath,
                allowedTypes: [UTType(filenameExtension: "vim") ?? .data],
                expectsDirectory: false,
                allowedExtensions: ["vim"]
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
        let palette: [(color: Color?, presetIndex: Int?)] =
            [(color: nil, presetIndex: nil)] + presets.enumerated().map { ($0.element, $0.offset) }

        return VStack(alignment: .leading, spacing: 6) {
            Text("Color")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 12) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(18), spacing: 6), count: 6), alignment: .leading,
                    spacing: 6
                ) {
                    ForEach(Array(palette.enumerated()), id: \.offset) { _, item in
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
                .frame(width: 140, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "paintpalette")
                            .foregroundStyle(.secondary)
                        Text(String(localized: "Custom"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    ColorPicker("", selection: $state.color, supportsOpacity: false)
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
        let resolvedURL: URL? = {
            if state.isSession {
                return state.normalizedSessionURL ?? loadedEntry?.sessionPath
                    ?? (loadedEntry?.id.pathExtension.lowercased() == "vim" ? loadedEntry?.id : nil)
            }
            return state.normalizedProjectURL ?? loadedEntry?.id
        }()

        let displayName: String = {
            let trimmed = state.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
            return loadedEntry?.name ?? resolvedURL?.lastPathComponent ?? String(localized: "Untitled")
        }()

        let displayPath = resolvedURL.map { ProjectPathFormatter.displayPath($0) } ?? "-"
        let iconColor = state.useCustomColor ? state.color : Color.secondary
        let emojiText = state.emojiValue.isEmpty ? "🙂" : state.emojiValue
        let emojiFontSize: CGFloat = emojiText.count > 1 ? 20 : 28

        let card = HStack(spacing: 12) {
            Group {
                switch state.iconMode {
                case .default:
                    Image(systemName: state.isSession ? "doc.text.fill" : "folder.fill")
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
        let candidates = [
            "folder.fill", "terminal.fill", "doc.text.fill", "tray.fill",
            "shippingbox.fill", "cube.fill", "memorychip.fill",
            "gearshape.fill", "wrench.and.screwdriver.fill", "hammer.fill", "bolt.fill", "sparkles",
            "tag.fill", "bookmark.fill", "link", "paperplane.fill", "star.fill", "heart.fill", "flame.fill",
            "leaf.fill", "globe", "briefcase.fill", "camera.fill", "paintbrush.fill", "chart.bar.fill",
            "map.fill", "music.note", "gamecontroller.fill", "graduationcap.fill",
        ]
        return candidates.filter(isValidSymbolName)
    }

    private func isValidSymbolName(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

}

// MARK: - Actions

extension ProjectEditorView {
    fileprivate func loadInitialData() {
        guard let entry = projectRegistry.entry(for: projectID) else { return }
        loadedEntry = entry
        state = EditorState(entry: entry)
    }

    fileprivate func save() {
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
    let allowedExtensions: [String]?

    @State private var isPickerPresented = false

    init(
        path: Binding<String>,
        allowedTypes: [UTType],
        expectsDirectory: Bool,
        allowedExtensions: [String]? = nil
    ) {
        self._path = path
        self.allowedTypes = allowedTypes
        self.expectsDirectory = expectsDirectory
        self.allowedExtensions = allowedExtensions
    }

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
                        guard accepts(url) else { return }
                        path = url.path(percentEncoded: false)
                    }
                }
        }
    }

    private func handleDrop(_ urls: [URL]) -> Bool {
        guard let url = urls.first else { return false }
        guard accepts(url) else { return false }

        if expectsDirectory {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                isDir.boolValue
            else { return false }
        }

        path = url.path(percentEncoded: false)
        return true
    }

    private func accepts(_ url: URL) -> Bool {
        guard let allowedExtensions, !allowedExtensions.isEmpty else { return true }
        let ext = url.pathExtension.lowercased()
        return allowedExtensions.contains(ext)
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
        .black, .white, .red, .orange, .yellow, .green,
        .mint, .teal, .blue, .indigo, .purple,
    ]

    var name = ""
    var projectPath = ""
    var sessionPath = ""
    var isSession = false
    var iconMode: IconMode = .default
    var symbolName = "folder.fill"
    var emojiValue = ""
    var useCustomColor = false
    var color: Color = .orange
    var selectedPresetIndex: Int?

    init() {}

    init(entry: ProjectEntry) {
        isSession = entry.isSession

        if let entryName = entry.name, !entryName.isEmpty {
            name = entryName
        } else {
            name = entry.id.deletingPathExtension().lastPathComponent
        }

        if isSession {
            if let sessionURL = entry.sessionPath {
                sessionPath = ProjectPathFormatter.displayPath(sessionURL)
                projectPath = ProjectPathFormatter.displayPath(sessionURL.deletingLastPathComponent())
            } else if entry.id.pathExtension.lowercased() == "vim" {
                sessionPath = ProjectPathFormatter.displayPath(entry.id)
                projectPath = ProjectPathFormatter.displayPath(entry.id.deletingLastPathComponent())
            }
        } else {
            projectPath = ProjectPathFormatter.displayPath(entry.id)
            sessionPath = ""
        }

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

    var canSave: Bool {
        isSession ? normalizedSessionURL != nil : normalizedProjectURL != nil
    }

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
        let iconValue = buildIconValue()

        if isSession {
            guard let sessionURL = normalizedSessionURL else { return nil }
            return ProjectEntry(
                id: sessionURL,
                name: buildName(for: sessionURL),
                icon: iconValue,
                colorHex: useCustomColor ? color.hexString() : nil,
                sessionPath: sessionURL
            )
        }

        guard let projectURL = normalizedProjectURL else { return nil }
        return ProjectEntry(
            id: projectURL,
            name: buildName(for: projectURL),
            icon: iconValue,
            colorHex: useCustomColor ? color.hexString() : nil,
            sessionPath: nil
        )
    }

    var normalizedProjectURL: URL? {
        let trimmed = projectPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let expanded = ProjectPathFormatter.expandTilde(trimmed)
        return ProjectRegistry.normalizeID(URL(fileURLWithPath: expanded))
    }

    var normalizedSessionURL: URL? {
        let trimmed = sessionPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let expanded = ProjectPathFormatter.expandTilde(trimmed)
        let url = URL(fileURLWithPath: expanded)
        guard url.pathExtension.lowercased() == "vim" else { return nil }
        return ProjectRegistry.normalizeSessionPath(url)
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

    private func buildName(for url: URL) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? url.deletingPathExtension().lastPathComponent : trimmed
    }
}

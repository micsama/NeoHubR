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
        .frame(width: 380)
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
        let title: LocalizedStringKey = "Project Name"
        return fieldGroup(title) {
            TextField(title, text: $state.name)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var projectField: some View {
        pathField(
            title: "Project Path",
            path: $state.projectPath,
            allowedTypes: [.folder],
            expectsDirectory: true,
            isValid: state.isProjectPathValid
        )
    }

    private var sessionField: some View {
        pathField(
            title: "Session.vim Path",
            path: $state.sessionPath,
            allowedTypes: [.data],
            expectsDirectory: false
        )
    }

    private var iconField: some View {
        fieldGroup("Icon") {
            Button {
                isIconPickerPresented = true
            } label: {
                HStack(spacing: 8) {
                    iconPreview
                    Text(iconTitle)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.quaternary)
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isIconPickerPresented, arrowEdge: .bottom) {
                iconPickerPopover
            }
        }
    }

    private var colorField: some View {
        fieldGroup("Color") {
            HStack(spacing: 8) {
                ColorSwatch(
                    color: nil,
                    isSelected: !state.useCustomColor
                ) {
                    state.selectNoneColor()
                }

                ForEach(ColorOption.presets) { option in
                    ColorSwatch(
                        color: option.color,
                        isSelected: state.useCustomColor && state.selectedPresetID == option.id
                    ) {
                        state.selectPresetColor(option)
                    }
                }

                Divider()
                    .frame(height: 18)
                    .padding(.horizontal, 4)

                HStack(spacing: 6) {
                    Image(systemName: "paintpalette")
                        .foregroundStyle(.secondary)
                    ColorPicker("Custom", selection: customColorBinding, supportsOpacity: false)
                        .labelsHidden()
                }
            }
        }
    }

    private var actionsBar: some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.escape, modifiers: [])
            Button("Save") { save() }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!state.canSave)
        }
        .padding(.top, 4)
    }

    private var previewCard: some View {
        let previewEntry = state.previewEntry(fallback: loadedEntry)
        let displayName = state.displayName(fallback: loadedEntry)
        let displayPath = state.displayPath(fallback: loadedEntry)

        return glassCard {
            HStack(spacing: 12) {
                ProjectIconView(
                    entry: previewEntry,
                    fallbackSystemName: "folder.fill",
                    size: 28,
                    isInvalid: false,
                    fallbackColor: .secondary
                )

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
        }
    }

    private func fieldGroup<Content: View>(
        _ title: LocalizedStringKey,
        isValid: Bool? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(title, isValid: isValid)
            content()
        }
    }

    @ViewBuilder
    private func fieldLabel(_ title: LocalizedStringKey, isValid: Bool?) -> some View {
        if let isValid {
            Text(title)
                .foregroundStyle(isValid ? AnyShapeStyle(.primary) : AnyShapeStyle(.red))
                .font(.caption)
                .fontWeight(isValid ? .regular : .bold)
        } else {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func pathField(
        title: LocalizedStringKey,
        path: Binding<String>,
        allowedTypes: [UTType],
        expectsDirectory: Bool,
        isValid: Bool? = nil
    ) -> some View {
        fieldGroup(title, isValid: isValid) {
            PathField(
                path: path,
                allowedTypes: allowedTypes,
                expectsDirectory: expectsDirectory
            )
        }
    }

    private var iconPreview: some View {
        Group {
            switch state.iconMode {
            case .default:
                Image(systemName: "folder.fill")
            case .symbol:
                Image(systemName: state.symbolName)
            case .emoji:
                Text(state.emojiValue.isEmpty ? "🙂" : state.emojiValue)
            }
        }
        .font(.system(size: 14))
        .frame(width: 18, height: 18)
    }

    private var iconTitle: String {
        switch state.iconMode {
        case .default:
            return String(localized: "Default")
        case .symbol:
            return state.symbolName
        case .emoji:
            return state.emojiValue.isEmpty ? String(localized: "Emoji") : state.emojiValue
        }
    }

    private var iconPickerPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Symbol")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: iconGridColumns, spacing: 8) {
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

            Divider()

            HStack(spacing: 8) {
                Button(String(localized: "Default")) {
                    state.iconMode = .default
                    state.symbolName = "folder.fill"
                    state.emojiValue = ""
                }
                .buttonStyle(.bordered)

                Spacer()

                TextField(String(localized: "Emoji"), text: $state.emojiValue)
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: state.emojiValue) { _, newValue in
                        if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            state.iconMode = .emoji
                        }
                    }
            }
        }
        .padding(12)
        .frame(width: 260)
    }

    private var iconGridColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(32), spacing: 8), count: 6)
    }

    private var iconOptions: [String] {
        [
            "folder.fill",
            "folder",
            "terminal.fill",
            "hammer.fill",
            "wrench.and.screwdriver.fill",
            "gearshape.fill",
            "chevron.left.slash.chevron.right",
            "curlybraces",
            "swift",
            "shippingbox.fill",
            "link",
            "sparkles",
            "bolt.fill",
            "doc.text.fill",
            "tray.full.fill",
            "bookmark.fill",
            "paperplane.fill",
            "cube.transparent.fill"
        ]
    }

    private var customColorBinding: Binding<Color> {
        Binding(
            get: { state.color },
            set: { newValue in
                state.selectCustomColor(newValue)
            }
        )
    }

    @ViewBuilder
    private func glassCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if #available(macOS 26.0, *) {
            content()
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            content()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
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

private enum IconMode: String, CaseIterable {
    case `default`, symbol, emoji
}

// MARK: - ColorOption

private struct ColorOption: Identifiable {
    let id: String
    let color: Color

    static let presets: [ColorOption] = [
        .init(id: "red", color: .red),
        .init(id: "orange", color: .orange),
        .init(id: "yellow", color: .yellow),
        .init(id: "green", color: .green),
        .init(id: "mint", color: .mint),
        .init(id: "blue", color: .blue),
        .init(id: "indigo", color: .indigo),
        .init(id: "purple", color: .purple)
    ]

    static func matchingID(for color: Color) -> String? {
        guard let hex = color.hexString() else { return nil }
        return presets.first { $0.color.hexString() == hex }?.id
    }
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
    var name = ""
    var projectPath = ""
    var sessionPath = ""
    var iconMode: IconMode = .default
    var symbolName = "folder.fill"
    var emojiValue = ""
    var useCustomColor = false
    var color: Color = .orange
    var selectedPresetID: String?

    init() {}

    init(entry: ProjectEntry) {
        name = entry.name ?? ""
        projectPath = ProjectPathFormatter.displayPath(entry.id)
        sessionPath = entry.sessionPath.map { ProjectPathFormatter.displayPath($0) } ?? ""

        if let customColor = entry.customColor {
            useCustomColor = true
            color = customColor
            selectedPresetID = ColorOption.matchingID(for: customColor)
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
        selectedPresetID = nil
    }

    mutating func selectPresetColor(_ option: ColorOption) {
        useCustomColor = true
        selectedPresetID = option.id
        color = option.color
    }

    mutating func selectCustomColor(_ newColor: Color) {
        useCustomColor = true
        selectedPresetID = nil
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

    func previewEntry(fallback entry: ProjectEntry?) -> ProjectEntry {
        let fallbackURL = entry?.id ?? URL(fileURLWithPath: "/")
        let previewURL = normalizedProjectURL ?? fallbackURL
        return ProjectEntry(
            id: previewURL,
            name: displayName(fallback: entry),
            icon: buildIconValue(),
            colorHex: useCustomColor ? color.hexString() : nil
        )
    }

    func displayName(fallback entry: ProjectEntry?) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return trimmedName
        }
        if let entryName = entry?.name, !entryName.isEmpty {
            return entryName
        }
        let fallbackURL = normalizedProjectURL ?? entry?.id
        return fallbackURL?.lastPathComponent ?? String(localized: "Untitled")
    }

    func displayPath(fallback entry: ProjectEntry?) -> String {
        if let url = normalizedProjectURL {
            return ProjectPathFormatter.displayPath(url)
        }
        if let id = entry?.id {
            return ProjectPathFormatter.displayPath(id)
        }
        return "-"
    }

    private var normalizedProjectURL: URL? {
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

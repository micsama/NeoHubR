import KeyboardShortcuts
import NeoHubRLib
import SwiftUI

// MARK: - Entry Model

@MainActor
private struct SwitcherItem: Identifiable {
    let id: URL
    let entry: ProjectEntry
    let editor: Editor?
    let isStarred: Bool
    let isInvalid: Bool

    var isActive: Bool { editor != nil }

    var name: String {
        if let name = entry.name, !name.isEmpty {
            return name
        }
        if entry.isSession {
            return entry.id.deletingPathExtension().lastPathComponent
        }
        return entry.id.lastPathComponent
    }

    var displayPath: String {
        ProjectPathFormatter.displayPath(entry.id)
    }

    var isSession: Bool {
        entry.isSession
    }
}

// MARK: - ViewModel

@Observable
@MainActor
private final class SwitcherViewModel {
    private let editorStore: EditorStore
    let projectRegistry: ProjectRegistryStore
    private let appSettings: AppSettingsStore
    private let activationManager: ActivationManager
    var onDismiss: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    var searchText = ""
    var selectedID: URL?
    var refreshToken: Int = 0
    var switcherMaxItems: Int { appSettings.switcherMaxItems }

    init(
        editorStore: EditorStore,
        projectRegistry: ProjectRegistryStore,
        appSettings: AppSettingsStore,
        activationManager: ActivationManager
    ) {
        self.editorStore = editorStore
        self.projectRegistry = projectRegistry
        self.appSettings = appSettings
        self.activationManager = activationManager
    }

    func setActions(
        onDismiss: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.onDismiss = onDismiss
        self.onOpenSettings = onOpenSettings
    }

    // MARK: - Computed

    var entries: [SwitcherItem] {
        let maxItems = AppSettings.clampSwitcherMaxItems(appSettings.switcherMaxItems)
        let editors = editorStore.getEditors(sortedFor: .switcher)
        let projectIndex = projectIndexByID()
        var result: [SwitcherItem] = []
        result.reserveCapacity(maxItems)

        var activeIDs: Set<URL> = []
        for editor in editors {
            if result.count >= maxItems { return result }
            let normalizedID = ProjectRegistry.normalizeID(editor.id.id)
            activeIDs.insert(normalizedID)

            if let (entry, isStarred) = projectIndex[normalizedID] {
                result.append(
                    SwitcherItem(
                        id: normalizedID,
                        entry: entry,
                        editor: editor,
                        isStarred: isStarred,
                        isInvalid: false
                    )
                )
            } else {
                let fallbackEntry = ProjectEntry(id: normalizedID, name: editor.name)
                result.append(
                    SwitcherItem(
                        id: normalizedID,
                        entry: fallbackEntry,
                        editor: editor,
                        isStarred: false,
                        isInvalid: false
                    )
                )
            }
        }

        appendProjects(
            projectRegistry.starredEntries,
            isStarred: true,
            excluding: activeIDs,
            into: &result,
            maxItems: maxItems
        )
        appendProjects(
            projectRegistry.recentEntries,
            isStarred: false,
            excluding: activeIDs,
            into: &result,
            maxItems: maxItems
        )

        return result
    }

    private func projectIndexByID() -> [URL: (ProjectEntry, Bool)] {
        var result: [URL: (ProjectEntry, Bool)] = [:]
        for entry in projectRegistry.starredEntries {
            result[ProjectRegistry.normalizeID(entry.id)] = (entry, true)
        }
        for entry in projectRegistry.recentEntries {
            result[ProjectRegistry.normalizeID(entry.id)] = (entry, false)
        }
        return result
    }

    private func appendProjects(
        _ projects: [ProjectEntry],
        isStarred: Bool,
        excluding activeIDs: Set<URL>,
        into result: inout [SwitcherItem],
        maxItems: Int
    ) {
        for project in projects {
            if result.count >= maxItems { return }
            let normalizedID = ProjectRegistry.normalizeID(project.id)
            guard !activeIDs.contains(normalizedID) else { continue }
            result.append(
                SwitcherItem(
                    id: normalizedID,
                    entry: project,
                    editor: nil,
                    isStarred: isStarred,
                    isInvalid: projectRegistry.isInvalid(project)
                )
            )
        }
    }

    var filteredEntries: [SwitcherItem] {
        guard !searchText.isEmpty else { return entries }
        return entries.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.displayPath.localizedCaseInsensitiveContains(searchText)
        }
    }

    var isEmpty: Bool {
        editorStore.getEditors().isEmpty && projectRegistry.entries.isEmpty
    }

    // MARK: - Navigation

    func selectPrevious() {
        let entries = filteredEntries
        guard !entries.isEmpty else { return }

        guard let currentID = selectedID,
              let currentIndex = entries.firstIndex(where: { $0.id == currentID })
        else {
            selectedID = entries.last?.id
            return
        }

        let newIndex = currentIndex > 0 ? currentIndex - 1 : entries.count - 1
        selectedID = entries[newIndex].id
    }

    func selectNext() {
        let entries = filteredEntries
        guard !entries.isEmpty else { return }

        guard let currentID = selectedID,
              let currentIndex = entries.firstIndex(where: { $0.id == currentID })
        else {
            selectedID = entries.first?.id
            return
        }

        let newIndex = currentIndex < entries.count - 1 ? currentIndex + 1 : 0
        selectedID = entries[newIndex].id
    }

    // MARK: - Selection Reset

    func resetSelectionIfNeeded() {
        let filtered = filteredEntries
        if let currentID = selectedID,
           filtered.contains(where: { $0.id == currentID }) {
            return
        }
        selectedID = filtered.first?.id
    }

    // MARK: - Actions

    func activate(_ entry: SwitcherItem) {
        if let editor = entry.editor {
            editor.activate()
        } else {
            editorStore.openProject(entry.entry)
        }
    }

    func activateSelected() {
        guard let selectedID,
              let entry = filteredEntries.first(where: { $0.id == selectedID })
        else { return }
        activate(entry)
    }

    func activate(at index: Int) {
        let entries = filteredEntries
        guard entries.indices.contains(index) else { return }
        let entry = entries[index]
        selectedID = entry.id
        activate(entry)
    }

    func quitSelected() {
        let entries = filteredEntries
        guard let selectedID,
              let currentIndex = entries.firstIndex(where: { $0.id == selectedID }),
              let editor = entries[currentIndex].editor
        else { return }

        let editorCount = entries.filter { $0.isActive }.count
        if editorCount == 1 {
            activationManager.activateTarget()
        }

        if currentIndex == entries.count - 1 && currentIndex > 0 {
            self.selectedID = entries[currentIndex - 1].id
        }

        editor.quit()
    }

    func quitAll() {
        Task {
            activationManager.activateTarget()
            await editorStore.quitAllEditors()
        }
        onDismiss()
    }
}
// MARK: - Window

@MainActor
final class SwitcherWindow {
    private let panel: NSPanel
    private let viewModel: SwitcherViewModel
    private let activationManager: ActivationManager
    private let editorStore: EditorStore
    private let selfRef: SwitcherWindowRef

    private var isVisible = false

    init(
        editorStore: EditorStore,
        selfRef: SwitcherWindowRef,
        activationManager: ActivationManager,
        appSettings: AppSettingsStore,
        projectRegistry: ProjectRegistryStore
    ) {
        self.editorStore = editorStore
        self.selfRef = selfRef
        self.activationManager = activationManager

        self.viewModel = SwitcherViewModel(
            editorStore: editorStore,
            projectRegistry: projectRegistry,
            appSettings: appSettings,
            activationManager: activationManager
        )

        self.panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 380),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configurePanel()
        viewModel.setActions(
            onDismiss: { [weak self] in self?.hide() },
            onOpenSettings: { [weak self] in self?.openSettings() }
        )

        let contentView = SwitcherContentView(viewModel: viewModel)
        panel.contentView = NSHostingView(rootView: contentView)

        setupShortcuts()
    }

    private func configurePanel() {
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true
        panel.setFrameAutosaveName(APP_NAME)

        for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(type)?.isHidden = true
        }
    }

    private func setupShortcuts() {
        KeyboardShortcuts.onKeyDown(for: .toggleSwitcher) { [weak self] in
            self?.handleToggleSwitcher()
        }
        KeyboardShortcuts.onKeyDown(for: .toggleLastActiveEditor) { [weak self] in
            self?.handleToggleLastActive()
        }
    }

    private func handleToggleSwitcher() {
        editorStore.pruneDeadEditors()
        let editors = editorStore.getEditors()

        guard editors.count == 1, let editor = editors.first else {
            toggle()
            return
        }

        let frontApp = NSWorkspace.shared.frontmostApplication
        if frontApp?.processIdentifier == editor.processIdentifier {
            guard activationManager.activationTarget != nil else {
                toggle()
                return
            }
            activationManager.activateTarget()
            if activationManager.activationTarget == nil {
                toggle()
            }
            return
        }

        activationManager.setActivationTarget(
            currentApp: frontApp,
            switcherWindow: selfRef,
            editors: editors
        )
        editor.activate()
    }

    private func handleToggleLastActive() {
        editorStore.pruneDeadEditors()
        let editors = editorStore.getEditors(sortedFor: .lastActiveEditor)

        guard let editor = editors.first else {
            toggle()
            return
        }

        let frontApp = NSWorkspace.shared.frontmostApplication
        if frontApp?.processIdentifier == editor.processIdentifier {
            NSRunningApplication(processIdentifier: editor.processIdentifier)?.hide()
        } else {
            if let app = frontApp {
                activationManager.setActivationTarget(
                    currentApp: app,
                    switcherWindow: selfRef,
                    editors: editors
                )
            }
            NSRunningApplication(processIdentifier: editor.processIdentifier)?.activate()
        }
    }

    private func toggle() {
        isVisible ? hide() : show()
    }

    private func show() {
        editorStore.pruneDeadEditors()
        activationManager.setActivationTarget(
            currentApp: NSWorkspace.shared.frontmostApplication,
            switcherWindow: selfRef,
            editors: editorStore.getEditors()
        )
        viewModel.projectRegistry.refreshValidity()
        viewModel.refreshToken &+= 1

        isVisible = true
        viewModel.searchText = ""
        viewModel.selectedID = viewModel.entries.first?.id
        centerOnScreen()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        panel.orderOut(nil)

        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == APP_BUNDLE_ID {
            activationManager.activateTarget()
        }
    }

    func isHidden() -> Bool { !isVisible }

    func isSameWindow(_ window: NSWindow) -> Bool { panel == window }

    func openSettings() {
        hide()
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private func centerOnScreen() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let x = frame.midX - panel.frame.width / 2
        let y = frame.midY - panel.frame.height / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - SwitcherWindowRef

@MainActor
final class SwitcherWindowRef {
    private weak var window: SwitcherWindow?

    init() {}

    func set(_ window: SwitcherWindow) {
        self.window = window
    }

    func isSameWindow(_ window: NSWindow) -> Bool {
        self.window?.isSameWindow(window) ?? false
    }
}
// MARK: - Search Field (AppKit)

private struct SwitcherSearchField: NSViewRepresentable {
    @Binding var text: String
    var onUp: () -> Void
    var onDown: () -> Void
    var onReturn: () -> Void
    var onEscape: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.placeholderString = String(localized: "Search")
        field.isBordered = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 16)

        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }

        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SwitcherSearchField

        init(_ parent: SwitcherSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTextField {
                parent.text = field.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onUp()
                return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onDown()
                return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.onReturn()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEscape()
                return true
            case #selector(NSResponder.insertTab(_:)):
                parent.onDown()
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                parent.onUp()
                return true
            default:
                return false
            }
        }
    }
}
// MARK: - Content View

private struct SwitcherContentView: View {
    @Bindable var viewModel: SwitcherViewModel
    @Namespace private var selectionAnimation

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isEmpty {
                EmptyStateView(viewModel: viewModel)
            } else {
                MainLayoutView(
                    viewModel: viewModel,
                    animation: selectionAnimation
                )
            }
        }
        .frame(width: 720, height: 380)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                .blendMode(.overlay)
        )
        .onKeyPress(phases: .down) { press in
            handleGlobalKeyPress(press)
        }
        .onChange(of: viewModel.switcherMaxItems) { _, _ in
            viewModel.refreshToken &+= 1
            viewModel.resetSelectionIfNeeded()
        }
    }

    private func handleGlobalKeyPress(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.contains(.command) else { return .ignored }

        if let char = press.characters.first,
           let digit = char.wholeNumberValue,
           digit >= 0 && digit <= 9 {
            viewModel.activate(at: digit == 0 ? 9 : digit - 1)
            return .handled
        }

        switch press.characters {
        case "w":
            viewModel.onDismiss()
            return .handled
        case "d":
            viewModel.quitSelected()
            return .handled
        case "D":
            viewModel.quitAll()
            return .handled
        default:
            return .ignored
        }
    }
}

// MARK: - Main Layout

private struct MainLayoutView: View {
    @Bindable var viewModel: SwitcherViewModel
    let animation: Namespace.ID

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)

                SwitcherSearchField(
                    text: $viewModel.searchText,
                    onUp: { viewModel.selectPrevious() },
                    onDown: { viewModel.selectNext() },
                    onReturn: { viewModel.activateSelected() },
                    onEscape: { viewModel.onDismiss() }
                )
            }
            .padding(14)
            .background(.quaternary.opacity(0.5))
            .overlay(alignment: .bottom) {
                Divider().opacity(0.5)
            }
            .onChange(of: viewModel.searchText) { _, _ in
                viewModel.resetSelectionIfNeeded()
            }

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        let entries = viewModel.filteredEntries

                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            let isSelected = entry.id == viewModel.selectedID
                            let needsGap = entry.isActive
                                && index + 1 < entries.count
                                && !entries[index + 1].isActive

                            SwitcherRow(
                                entry: entry,
                                index: index,
                                isSelected: isSelected,
                                query: viewModel.searchText,
                                animation: animation
                            )
                            .id(entry.id)
                            .padding(.bottom, needsGap ? 12 : 0)
                            .onTapGesture {
                                viewModel.activate(at: index)
                            }
                        }
                    }
                    .padding(10)
                    .padding(.bottom, 20)
                }
                .id(viewModel.refreshToken)
                .onChange(of: viewModel.selectedID) { _, newID in
                    guard let newID else { return }
                    withAnimation(.spring(response: 0.25, dampingFraction: 1.0)) {
                        proxy.scrollTo(newID, anchor: nil)
                    }
                }
                .onAppear {
                    if let id = viewModel.selectedID {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }

            Divider().opacity(0.5)

            HStack {
                Spacer()
                actionButton(title: "Quit Selected", shortcut: "⌘D") { viewModel.quitSelected() }
                actionButton(title: "Quit All", shortcut: "⇧⌘D") { viewModel.quitAll() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }

    private func actionButton(title: String, shortcut: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                Text(shortcut)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Row View

private struct SwitcherRow: View {
    let entry: SwitcherItem
    let index: Int
    let isSelected: Bool
    let query: String
    let animation: Namespace.ID

    var body: some View {
        let iconStyle: (fill: Color, stroke: Color) = {
            if entry.isActive {
                return (Color.green.opacity(0.12), .green)
            }
            if entry.isStarred {
                return (Color.yellow.opacity(0.12), .yellow)
            }
            return (.clear, .clear)
        }()

        HStack(spacing: 12) {
            ProjectIconView(
                entry: entry.entry,
                fallbackSystemName: "folder.fill",
                size: 16,
                isInvalid: entry.isInvalid,
                fallbackColor: .secondary
            )
            .frame(width: 20, height: 20)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconStyle.fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(iconStyle.stroke, lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    highlightedTextView(
                        text: entry.name,
                        font: .system(size: 14, weight: .medium),
                        color: entry.isInvalid ? .secondary : .primary
                    )

                    if entry.isInvalid { statusTag("Not available") }
                    if entry.isSession { statusTag("Session") }
                }

                highlightedTextView(
                    text: entry.displayPath,
                    font: .system(size: 11),
                    color: entry.isInvalid ? .secondary.opacity(0.6) : .secondary
                )
                .lineLimit(1)
            }

            Spacer()

            if index < 10 {
                Text("⌘\(index == 9 ? 0 : index + 1)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(isSelected ? .secondary : .tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isSelected ? .white.opacity(0.2) : .primary.opacity(0.05))
                    )
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .matchedGeometryEffect(id: "highlight", in: animation)
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            }
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 1)
            }
        }
        .overlay(alignment: .leading) {
            if entry.isActive {
                Capsule()
                    .fill(Color.green)
                    .frame(width: 3, height: 32)
                    .padding(.leading, 1)
            }
        }
    }

    @ViewBuilder
    private func statusTag(_ text: String) -> some View {
        Text("(\(String(localized: String.LocalizationValue(text))))")
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private func highlightedTextView(text: String, font: Font, color: Color) -> some View {
        Text(highlightedText(for: text, query: query))
            .font(font)
            .foregroundStyle(color)
    }

    private func highlightedText(for text: String, query: String) -> AttributedString {
        guard !query.isEmpty else { return AttributedString(text) }

        var attributed = AttributedString(text)
        let lowerText = text.lowercased()
        let lowerQuery = query.lowercased()
        var searchRange = lowerText.startIndex..<lowerText.endIndex

        while let range = lowerText.range(of: lowerQuery, options: [], range: searchRange) {
            if let attrRange = Range(range, in: attributed) {
                attributed[attrRange].foregroundColor = .accentColor
            }
            searchRange = range.upperBound..<lowerText.endIndex
        }
        return attributed
    }
}

private struct EmptyStateView: View {
    let viewModel: SwitcherViewModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No running Neovide instances")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("Settings") { viewModel.onOpenSettings() }
                    .buttonStyle(.bordered)
                Button("Close") { viewModel.onDismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

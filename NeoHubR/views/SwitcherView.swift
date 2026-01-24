import KeyboardShortcuts
import NeoHubRLib
import SwiftUI

// MARK: - Entry Model

@MainActor
private enum SwitcherEntry: Identifiable {
    case editor(Editor, ProjectEntry?, isStarred: Bool)
    case project(ProjectEntry, isInvalid: Bool, isStarred: Bool)

    nonisolated var id: String {
        switch self {
        case .editor(let e, _, _): return "editor:\(ObjectIdentifier(e))"
        case .project(let p, _, _): return "project:\(p.id.absoluteString)"
        }
    }

    var name: String {
        switch self {
        case .editor(let e, let project, _):
            if let project, let name = project.name, !name.isEmpty {
                return name
            }
            return e.name
        case .project(let p, _, _): return p.name ?? p.id.lastPathComponent
        }
    }

    var displayPath: String {
        switch self {
        case .editor(let e, let project, _):
            if let project {
                return ProjectPathFormatter.displayPath(project.id)
            }
            return e.displayPath
        case .project(let p, _, _): return ProjectPathFormatter.displayPath(p.id)
        }
    }

    var isEditor: Bool {
        switch self {
        case .editor: return true
        case .project: return false
        }
    }

    var isStarred: Bool {
        switch self {
        case .project(_, _, let isStarred): return isStarred
        case .editor(_, _, let isStarred): return isStarred
        }
    }

    var isSession: Bool {
        switch self {
        case .project(let p, _, _): return p.isSession
        case .editor(_, let project, _): return project?.isSession ?? false
        }
    }

    var isInvalid: Bool {
        switch self {
        case .project(_, let isInvalid, _): return isInvalid
        case .editor: return false
        }
    }

    var projectEntry: ProjectEntry? {
        switch self {
        case .project(let project, _, _):
            return project
        case .editor(_, let project, _):
            return project
        }
    }

}

extension SwitcherEntry: Hashable {
    nonisolated static func == (lhs: SwitcherEntry, rhs: SwitcherEntry) -> Bool {
        lhs.id == rhs.id
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - ViewModel

@Observable
@MainActor
private final class SwitcherViewModel {
    private let editorStore: EditorStore
    private let projectRegistry: ProjectRegistryStore
    private let appSettings: AppSettingsStore
    private let activationManager: ActivationManager
    private var onDismiss: () -> Void = {}
    private var onOpenSettings: () -> Void = {}

    var searchText = ""
    var selectedIndex: Int = 0
    var refreshToken: Int = 0

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

    var entries: [SwitcherEntry] {
        let maxItems = AppSettings.clampSwitcherMaxItems(appSettings.switcherMaxItems)
        let editors = editorStore.getEditors(sortedFor: .switcher)
        let starredMap = Dictionary(uniqueKeysWithValues: projectRegistry.starredEntries.map { ($0.id, $0) })
        let recentMap = Dictionary(uniqueKeysWithValues: projectRegistry.recentEntries.map { ($0.id, $0) })
        var result = editors.map { editor in
            let normalizedID = ProjectRegistry.normalizeID(editor.id.id)
            if let entry = starredMap[normalizedID] {
                return SwitcherEntry.editor(editor, entry, isStarred: true)
            }
            if let entry = recentMap[normalizedID] {
                return SwitcherEntry.editor(editor, entry, isStarred: false)
            }
            return SwitcherEntry.editor(editor, nil, isStarred: false)
        }

        guard result.count < maxItems else {
            return Array(result.prefix(maxItems))
        }

        let editorLocations = Set(editors.map { ProjectRegistry.normalizeID($0.id.id) })
        
        let starred = projectRegistry.starredEntries.filter { !editorLocations.contains($0.id) }
        let recent = projectRegistry.recentEntries.filter { !editorLocations.contains($0.id) }

        for project in starred where result.count < maxItems {
            result.append(.project(project, isInvalid: projectRegistry.isInvalid(project), isStarred: true))
        }

        for project in recent where result.count < maxItems {
            result.append(.project(project, isInvalid: projectRegistry.isInvalid(project), isStarred: false))
        }

        return result
    }

    var filteredEntries: [SwitcherEntry] {
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
        let count = filteredEntries.count
        guard count > 0 else { return }
        if selectedIndex > 0 {
            selectedIndex -= 1
        } else {
            selectedIndex = count - 1
        }
    }

    func selectNext() {
        let count = filteredEntries.count
        guard count > 0 else { return }
        if selectedIndex < count - 1 {
            selectedIndex += 1
        } else {
            selectedIndex = 0
        }
    }

    // MARK: - Actions

    func activate(_ entry: SwitcherEntry) {
        switch entry {
        case .editor(let editor, _, _):
            editor.activate()
        case .project(let project, _, _):
            editorStore.openProject(project)
        }
    }

    func activateSelected() {
        activate(at: selectedIndex)
    }

    func activate(at index: Int) {
        guard filteredEntries.indices.contains(index) else { return }
        selectedIndex = index
        activate(filteredEntries[index])
    }

    func quitSelected() {
        let entries = filteredEntries
        guard entries.indices.contains(selectedIndex),
            case .editor(let editor, _, _) = entries[selectedIndex]
        else { return }

        let editorCount = entries.filter { $0.isEditor }.count
        if editorCount == 1 {
            activationManager.activateTarget()
        }

        if selectedIndex == entries.count - 1 && selectedIndex > 0 {
            selectedIndex -= 1
        }

        editor.quit()
    }

    func quitAll() {
        Task {
            activationManager.activateTarget()
            await editorStore.quitAllEditors()
        }
        dismiss()
    }

    func dismiss() {
        onDismiss()
    }

    func openSettings() {
        onOpenSettings()
    }

    func onAppear() {
        searchText = ""
        selectedIndex = 0
    }

    func refreshForShow() {
        projectRegistry.refreshValidity()
        // Force a list rebuild when showing the switcher to refresh ordering and reset scroll position.
        refreshToken &+= 1
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
        activationManager.setActivationTarget(
            currentApp: NSWorkspace.shared.frontmostApplication,
            switcherWindow: selfRef,
            editors: editorStore.getEditors()
        )
        viewModel.refreshForShow()

        isVisible = true
        viewModel.onAppear()
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
                return true  // 返回 true 表示我们处理了，系统不要再移动光标了
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
                parent.onDown()  // Tab 映射为向下
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                parent.onUp()  // Shift+Tab 映射为向上
                return true
            default:
                return false  // 其他按键（如左右键、字母）交给系统默认处理
            }
        }
    }
}

// MARK: - Content View

private struct SwitcherContentView: View {
    @Bindable var viewModel: SwitcherViewModel

    var body: some View {
        Group {
            if viewModel.isEmpty {
                emptyView
            } else {
                listView
            }
        }
        .frame(width: 720, height: 380)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .onKeyPress(phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }

            if let char = press.characters.first,
                let digit = char.wholeNumberValue,
                digit >= 0 && digit <= 9
            {
                viewModel.activate(at: digit == 0 ? 9 : digit - 1)
                return .handled
            }

            switch press.characters {
            case "w":
                viewModel.dismiss()
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

    // MARK: - Empty State

    private var emptyView: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("No running Neovide instances")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("Settings") { viewModel.openSettings() }
                    .buttonStyle(.bordered)
                Button("Close") { viewModel.dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - List State

    private var listView: some View {
        VStack(spacing: 12) {
            searchField
            entryList
            bottomBar
        }
        .padding(18)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            SwitcherSearchField(
                text: $viewModel.searchText,
                onUp: { viewModel.selectPrevious() },
                onDown: { viewModel.selectNext() },
                onReturn: { viewModel.activateSelected() },
                onEscape: { viewModel.dismiss() }
            )
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .onChange(of: viewModel.searchText) { _, _ in
            viewModel.selectedIndex = 0
        }
    }

    private var entryList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(Array(viewModel.filteredEntries.enumerated()), id: \.element.id) { index, entry in
                    SwitcherRowView(entry: entry, index: index, query: viewModel.searchText)
                        .id(entry.id)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(index == viewModel.selectedIndex ? Color.accentColor.opacity(0.2) : Color.clear)
                        )
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                        .onTapGesture {
                            viewModel.activate(at: index)
                        }
                }
            }
            .id(viewModel.refreshToken)
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .onChange(of: viewModel.selectedIndex) { _, newIndex in
                if let entry = viewModel.filteredEntries[safe: newIndex] {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(entry.id, anchor: .center)
                    }
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            Spacer()

            Button {
                viewModel.quitSelected()
            } label: {
                HStack(spacing: 4) {
                    Text("Quit Selected")
                    Text("⌘D").foregroundStyle(.tertiary)
                }
            }

            Button {
                viewModel.quitAll()
            } label: {
                HStack(spacing: 4) {
                    Text("Quit All")
                    Text("⇧⌘D").foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .font(.system(size: 12))
    }
}

// MARK: - Row View

private struct SwitcherRowView: View {
    let entry: SwitcherEntry
    let index: Int
    let query: String

    var body: some View {
        HStack(spacing: 12) {
            icon

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    nameText
                    if entry.isInvalid {
                        Text("(\(String(localized: "Not available")))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    if entry.isSession {
                        Text("(\(String(localized: "Session")))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }

                Text(highlightedText(for: entry.displayPath, query: query))
                    .font(.system(size: 11))
                    .foregroundStyle(entry.isInvalid ? .tertiary : .secondary)
                    .lineLimit(1)
            }

            Spacer()

            if index < 10 {
                Text("⌘\(index == 9 ? 0 : index + 1)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var icon: some View {
        if entry.isEditor {
            Image("EditorIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
        } else {
            if let projectEntry = entry.projectEntry {
                ProjectIconView(
                    entry: projectEntry,
                    fallbackSystemName: entry.isStarred ? "star.circle.fill" : "folder.fill",
                    size: 16,
                    isInvalid: entry.isInvalid,
                    fallbackColor: .orange
                )
                .frame(width: 20, height: 20)
            }
        }
    }

    private var nameColor: Color {
        if entry.isEditor {
            return .primary
        }
        if entry.isInvalid {
            return .secondary
        }
        return entry.projectEntry?.customColor ?? .orange
    }

    @ViewBuilder
    private var nameText: some View {
        let text = Text(highlightedText(for: entry.name, query: query))
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(nameColor)

        if entry.isInvalid {
            text.strikethrough().italic()
        } else {
            text
        }
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

// MARK: - Collection Extension

extension Collection {
    fileprivate subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

import KeyboardShortcuts
import NeoHubLib
import SwiftUI

struct Key {
    static let ESC: UInt16 = 53
    static let TAB: UInt16 = 48
    static let ENTER: UInt16 = 36
    static let ARROW_UP: UInt16 = 126
    static let ARROW_DOWN: UInt16 = 125
    static let BACKSPACE: UInt16 = 51
    static let COMMA: UInt16 = 43
    static let W: UInt16 = 13
    static let Q: UInt16 = 12
    static let ONE: UInt16 = 18
    static let TWO: UInt16 = 19
    static let THREE: UInt16 = 20
    static let FOUR: UInt16 = 21
    static let FIVE: UInt16 = 23
    static let SIX: UInt16 = 22
    static let SEVEN: UInt16 = 26
    static let EIGHT: UInt16 = 28
    static let NINE: UInt16 = 25
    static let ZERO: UInt16 = 29

    static let commandNumberKeys: [UInt16] = [
        ONE, TWO, THREE, FOUR, FIVE, SIX, SEVEN, EIGHT, NINE, ZERO,
    ]
}

private enum SwitcherEntry: Identifiable {
    case editor(Editor, title: String, displayPath: String)
    case project(ProjectEntry, title: String, displayPath: String)

    var id: String {
        switch self {
        case .editor(let editor, _, _):
            return "editor:\(editor.id.id.path(percentEncoded: false))"
        case .project(let project, _, _):
            return "project:\(project.id.path(percentEncoded: false))"
        }
    }

    var title: String {
        switch self {
        case .editor(_, let title, _): return title
        case .project(_, let title, _): return title
        }
    }

    var displayPath: String {
        switch self {
        case .editor(_, _, let displayPath): return displayPath
        case .project(_, _, let displayPath): return displayPath
        }
    }

    var isEditor: Bool {
        if case .editor = self { return true }
        return false
    }

    var isStarred: Bool {
        if case .project(let project, _, _) = self { return project.isStarred }
        return false
    }
}

private enum DisplayPath {
    static func format(_ url: URL) -> String {
        let fullPath = url.path(percentEncoded: false)
        let pattern = "^/Users/[^/]+/"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return fullPath
        }

        let range = NSRange(fullPath.startIndex..., in: fullPath)
        return regex.stringByReplacingMatches(
            in: fullPath,
            options: [],
            range: range,
            withTemplate: "~/"
        )
    }
}

@MainActor
private enum SwitcherListLogic {
    static func filterEntries(
        editorStore: EditorStore,
        projectRegistry: ProjectRegistryStore,
        appSettings: AppSettingsStore,
        searchText: String
    ) -> [SwitcherEntry] {
        let entries = buildEntries(
            editorStore: editorStore,
            projectRegistry: projectRegistry,
            appSettings: appSettings
        )
        return entries.filter { entry in
            searchText.isEmpty
                || entry.title.localizedCaseInsensitiveContains(searchText)
                || entry.displayPath.localizedCaseInsensitiveContains(searchText)
        }
    }

    static func buildEntries(
        editorStore: EditorStore,
        projectRegistry: ProjectRegistryStore,
        appSettings: AppSettingsStore
    ) -> [SwitcherEntry] {
        let maxItems = AppSettings.clampSwitcherMaxItems(appSettings.switcherMaxItems)
        let editors = editorStore.getEditors(sortedFor: .switcher)
        var entries = editors.map {
            SwitcherEntry.editor($0, title: $0.name, displayPath: $0.displayPath)
        }

        if entries.count >= maxItems {
            return Array(entries.prefix(maxItems))
        }

        let editorLocations = Set(editors.map { $0.id.id })
        let projects = projectRegistry.entries.filter { !editorLocations.contains($0.id) }

        let starred =
            projects
            .filter { $0.isStarred }
            .sorted { lhs, rhs in
                let lhsOrder = lhs.pinnedOrder ?? Int.max
                let rhsOrder = rhs.pinnedOrder ?? Int.max
                if lhsOrder != rhsOrder {
                    return lhsOrder < rhsOrder
                }
                return (lhs.lastOpenedAt ?? .distantPast) > (rhs.lastOpenedAt ?? .distantPast)
            }

        let recent =
            projects
            .filter { !$0.isStarred }
            .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }

        for project in starred + recent {
            guard entries.count < maxItems else { break }
            entries.append(
                .project(
                    project,
                    title: project.name ?? project.id.lastPathComponent,
                    displayPath: DisplayPath.format(project.id)
                )
            )
        }

        return entries
    }

    static func handleKey(
        _ event: NSEvent,
        editorStore: EditorStore,
        projectRegistry: ProjectRegistryStore,
        appSettings: AppSettingsStore,
        searchText: String,
        selectedIndex: inout Int,
        switcherWindow: SwitcherWindow,
        settingsWindow: RegularWindow<SettingsView>,
        activationManager: ActivationManager
    ) -> NSEvent? {
        let entries = filterEntries(
            editorStore: editorStore,
            projectRegistry: projectRegistry,
            appSettings: appSettings,
            searchText: searchText
        )

        switch event.keyCode {
        case Key.ARROW_UP:
            if selectedIndex > 0 {
                selectedIndex -= 1
            }
            return nil
        case Key.ARROW_DOWN:
            if selectedIndex < entries.count - 1 {
                selectedIndex += 1
            }
            return nil
        case Key.TAB:
            selectedIndex = (selectedIndex + 1) % max(entries.count, 1)
            return nil
        case Key.ENTER:
            activateEntry(at: selectedIndex, entries: entries, selectedIndex: &selectedIndex, editorStore: editorStore)
            return nil
        case Key.BACKSPACE where event.modifierFlags.contains(.command):
            quitSelectedEditor(entries: entries, selectedIndex: &selectedIndex, activationManager: activationManager)
            return nil
        case Key.ESC:
            switcherWindow.hide()
            return nil
        case Key.COMMA where event.modifierFlags.contains(.command):
            switcherWindow.hide()
            settingsWindow.open()
            return nil
        case Key.W where event.modifierFlags.contains(.command):
            switcherWindow.hide()
            return nil
        case Key.Q where event.modifierFlags.contains(.command):
            quitAllEditors(editorStore: editorStore, activationManager: activationManager)
            return nil
        case _ where event.modifierFlags.contains(.command):
            if let index = commandNumberIndex(for: event.keyCode) {
                activateEntry(at: index, entries: entries, selectedIndex: &selectedIndex, editorStore: editorStore)
                return nil
            }
            return nil
        default:
            break
        }
        return event
    }

    static func quitSelectedEditor(
        entries: [SwitcherEntry],
        selectedIndex: inout Int,
        activationManager: ActivationManager
    ) {
        guard entries.indices.contains(selectedIndex) else {
            return
        }

        guard case .editor(let editor, _, _) = entries[selectedIndex] else {
            return
        }

        if selectedIndex == entries.count - 1 && selectedIndex != 0 {
            selectedIndex -= 1
        }

        let totalEditors = entries.filter { $0.isEditor }.count
        if totalEditors == 1 {
            activationManager.activateTarget()
        }

        editor.quit()
    }

    static func quitAllEditors(editorStore: EditorStore, activationManager: ActivationManager) {
        Task {
            activationManager.activateTarget()
            await editorStore.quitAllEditors()
        }
    }

    static func activateEntry(
        at index: Int,
        entries: [SwitcherEntry],
        selectedIndex: inout Int,
        editorStore: EditorStore
    ) {
        guard entries.indices.contains(index) else {
            return
        }
        selectedIndex = index
        switch entries[index] {
        case .editor(let editor, _, _):
            editor.activate()
        case .project(let project, _, _):
            editorStore.openProject(project)
        }
    }

    static func commandNumberIndex(for keyCode: UInt16) -> Int? {
        guard let index = Key.commandNumberKeys.firstIndex(of: keyCode) else {
            return nil
        }
        return index
    }
}

private final class KeyboardEventHandler: ObservableObject {
    var monitor: Any?
}

struct Layout {
    static let windowWidth: Int = 720
    static let windowHeight: Int = 380
    static let titlebarHeight: Int = 28
    static let contentTopInset: Int = 14
    static let titleAdjustment: Int = titlebarHeight - contentTopInset
    static let windowCornerRadius: CGFloat = 18
    static let windowContentPadding: CGFloat = 18
    static let searchFieldFontSize: CGFloat = 16
    static let searchFieldHeight: CGFloat = 36
    static let resultsFontSize: CGFloat = 15
    static let rowVerticalPadding: CGFloat = 9
    static let rowHorizontalPadding: CGFloat = 12
    static let listSpacing: CGFloat = 8
    static let footerSpacing: CGFloat = 10
    static let footerFontSize: CGFloat = 12
    static let shortcutFontSize: CGFloat = 12
}

private func shortcutLabel(for index: Int) -> String? {
    switch index {
    case 0...8:
        return "⌘\(index + 1)"
    case 9:
        return "⌘0"
    default:
        return nil
    }
}

struct GlassPalette {
    static let tint = Color(red: 0.25, green: 0.82, blue: 0.82)
    static let projectTint = Color(red: 0.98, green: 0.74, blue: 0.36)

    static func textPrimary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.88)
    }

    static func textSecondary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.55)
    }

    static func rowBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.5)
    }

    static func rowSelected(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.26) : Color.white.opacity(0.7)
    }

    static func projectSelected(for scheme: ColorScheme) -> Color {
        scheme == .dark ? projectTint.opacity(0.25) : projectTint.opacity(0.3)
    }

    static func stroke(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.08)
    }

    static func border(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1)
    }

    static func searchBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.65)
    }

    static func ambientShade(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.1) : Color.white.opacity(0.15)
    }
}

struct GlassBackgroundView: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        if #available(macOS 26, *) {
            let view = NSGlassEffectView()
            view.cornerRadius = Layout.windowCornerRadius
            return view
        }

        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = Layout.windowCornerRadius
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        if #available(macOS 26, *), let glassView = nsView as? NSGlassEffectView {
            glassView.cornerRadius = Layout.windowCornerRadius
            return
        }

        if let effectView = nsView as? NSVisualEffectView {
            effectView.layer?.cornerRadius = Layout.windowCornerRadius
        }
    }
}

@MainActor
final class SwitcherWindow: ObservableObject {
    private let editorStore: EditorStore
    private let settingsWindow: RegularWindow<SettingsView>
    private let selfRef: SwitcherWindowRef
    private let activationManager: ActivationManager
    private let appSettings: AppSettingsStore
    private let projectRegistry: ProjectRegistryStore

    private var window: NSWindow!

    @Published private var hidden: Bool = true

    init(
        editorStore: EditorStore,
        settingsWindow: RegularWindow<SettingsView>,
        selfRef: SwitcherWindowRef,
        activationManager: ActivationManager,
        appSettings: AppSettingsStore,
        projectRegistry: ProjectRegistryStore
    ) {
        self.editorStore = editorStore
        self.settingsWindow = settingsWindow
        self.selfRef = selfRef
        self.activationManager = activationManager
        self.appSettings = appSettings
        self.projectRegistry = projectRegistry

        let contentView = SwitcherView(
            editorStore: editorStore,
            switcherWindow: self,
            appSettings: appSettings,
            projectRegistry: projectRegistry,
            settingsWindow: settingsWindow,
            activationManager: activationManager
        )

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Layout.windowWidth, height: Layout.windowHeight),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.contentView = NSHostingView(rootView: contentView)
        window.backgroundColor = .clear

        window.setFrameAutosaveName(APP_NAME)
        window.isReleasedWhenClosed = false

        window.level = .floating
        window.collectionBehavior = .canJoinAllSpaces

        window.hasShadow = true
        window.isOpaque = false

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.showsToolbarButton = false

        let titleAdjustment = CGFloat(Layout.titleAdjustment)
        window.contentView!.frame = window.contentView!.frame.offsetBy(dx: 0, dy: titleAdjustment)
        window.contentView!.frame.size.height -= titleAdjustment
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.cornerRadius = Layout.windowCornerRadius
        window.contentView?.layer?.masksToBounds = true

        window.isMovableByWindowBackground = true

        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        WindowPlacement.centerOnCurrentScreen(window)

        KeyboardShortcuts.onKeyDown(for: .toggleLastActiveEditor) { [self] in
            self.handleLastActiveEditorToggle()
        }

        KeyboardShortcuts.onKeyDown(for: .toggleSwitcher) { [self] in
            self.handleSwitcherToggle()
        }
    }

    private func handleLastActiveEditorToggle() {
        let editors = editorStore.getEditors(sortedFor: .lastActiveEditor)

        if !editors.isEmpty {
            let editor = editors.first!
            let application = NSRunningApplication(processIdentifier: editor.processIdentifier)
            switch NSWorkspace.shared.frontmostApplication {
            case .some(let app):
                if app.processIdentifier == editor.processIdentifier {
                    application?.hide()
                } else {
                    activationManager.setActivationTarget(
                        currentApp: app,
                        switcherWindow: self.selfRef,
                        editors: editors
                    )
                    application?.activate()
                }
            case .none:
                let application = NSRunningApplication(processIdentifier: editor.processIdentifier)
                application?.hide()
            }
        } else {
            self.toggle()
        }
    }

    private func handleSwitcherToggle() {
        let editors = editorStore.getEditors()

        if editors.count == 1 {
            let editor = editors.first!

            switch NSWorkspace.shared.frontmostApplication {
            case .some(let app):
                if app.processIdentifier == editor.processIdentifier {
                    activationManager.activateTarget()
                    activationManager.setActivationTarget(
                        currentApp: app,
                        switcherWindow: self.selfRef,
                        editors: editors
                    )
                } else {
                    activationManager.setActivationTarget(
                        currentApp: app,
                        switcherWindow: self.selfRef,
                        editors: editors
                    )
                    editor.activate()
                }
            case .none:
                editor.activate()
            }
        } else {
            self.toggle()
        }
    }

    private func toggle() {
        if window.isVisible {
            self.hide()
        } else {
            self.show()
        }
    }

    private func show() {
        activationManager.setActivationTarget(
            currentApp: NSWorkspace.shared.frontmostApplication,
            switcherWindow: self.selfRef,
            editors: self.editorStore.getEditors()
        )

        self.hidden = false

        WindowPlacement.centerOnCurrentScreen(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func hide() {
        if self.hidden {
            return
        }

        self.hidden = true
        window.orderOut(nil)

        let currentApp = NSWorkspace.shared.frontmostApplication
        if currentApp?.bundleIdentifier == APP_BUNDLE_ID {
            activationManager.activateTarget()
        }
    }

    public func isHidden() -> Bool {
        return self.hidden
    }

    public func isSameWindow(_ window: NSWindow) -> Bool {
        self.window == window
    }
}

enum SwitcherState {
    case noEditors
    case oneEditor
    case manyEditors
}

struct SwitcherView: View {
    @ObservedObject var editorStore: EditorStore
    @ObservedObject var switcherWindow: SwitcherWindow
    @ObservedObject var appSettings: AppSettingsStore
    @ObservedObject var projectRegistry: ProjectRegistryStore

    let settingsWindow: RegularWindow<SettingsView>
    let activationManager: ActivationManager

    private var state: SwitcherState? {
        if switcherWindow.isHidden() {
            return nil
        }

        let editors = editorStore.getEditors()
        let projects = projectRegistry.entries

        if editors.isEmpty && projects.isEmpty {
            return .noEditors
        }

        if editors.count <= 1 {
            return .oneEditor
        }

        return .manyEditors
    }

    var body: some View {
        GlassSwitcherRoot(
            state: state,
            editorStore: editorStore,
            switcherWindow: switcherWindow,
            projectRegistry: projectRegistry,
            appSettings: appSettings,
            settingsWindow: settingsWindow,
            activationManager: activationManager
        )
    }
}

struct GlassSwitcherRoot: View {
    let state: SwitcherState?
    @ObservedObject var editorStore: EditorStore
    @ObservedObject var switcherWindow: SwitcherWindow
    @ObservedObject var projectRegistry: ProjectRegistryStore
    @ObservedObject var appSettings: AppSettingsStore

    let settingsWindow: RegularWindow<SettingsView>
    let activationManager: ActivationManager

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            GlassBackgroundView()
            RoundedRectangle(cornerRadius: Layout.windowCornerRadius)
                .fill(GlassPalette.ambientShade(for: colorScheme))
                .blendMode(.softLight)
            RoundedRectangle(cornerRadius: Layout.windowCornerRadius)
                .stroke(GlassPalette.border(for: colorScheme), lineWidth: 1)
            Group {
                switch state {
                case .noEditors:
                    GlassSwitcherEmptyView(
                        switcherWindow: switcherWindow,
                        settingsWindow: settingsWindow
                    )
                case .oneEditor, .manyEditors:
                    GlassSwitcherListView(
                        editorStore: editorStore,
                        switcherWindow: switcherWindow,
                        projectRegistry: projectRegistry,
                        appSettings: appSettings,
                        settingsWindow: settingsWindow,
                        activationManager: activationManager
                    )
                case .none:
                    EmptyView()
                }
            }
            .padding(Layout.windowContentPadding)
        }
        .clipShape(RoundedRectangle(cornerRadius: Layout.windowCornerRadius))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GlassSwitcherEmptyView: View {
    @ObservedObject var switcherWindow: SwitcherWindow

    let settingsWindow: RegularWindow<SettingsView>

    @StateObject private var keyboard = KeyboardEventHandler()
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(GlassPalette.rowBackground(for: colorScheme))
                    .frame(width: 68, height: 68)
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(GlassPalette.tint)
            }
            Text("No running Neovide instances")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(GlassPalette.textSecondary(for: colorScheme))
            HStack(spacing: 10) {
                Button("Settings") {
                    switcherWindow.hide()
                    settingsWindow.open()
                }
                .buttonStyle(GlassGhostButtonStyle())
                Button("Close") { switcherWindow.hide() }
                    .buttonStyle(GlassPrimaryButtonStyle())
                    .focused($focused)
            }
        }
        .onAppear {
            focused = true
            keyboard.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                switch event.keyCode {
                case Key.ESC:
                    switcherWindow.hide()
                    return nil
                case Key.COMMA where event.modifierFlags.contains(.command):
                    switcherWindow.hide()
                    settingsWindow.open()
                    return nil
                case Key.W where event.modifierFlags.contains(.command):
                    switcherWindow.hide()
                    return nil
                default:
                    break
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = keyboard.monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}

struct GlassSwitcherListView: View {
    @ObservedObject var editorStore: EditorStore
    @ObservedObject var switcherWindow: SwitcherWindow
    @ObservedObject var projectRegistry: ProjectRegistryStore
    @ObservedObject var appSettings: AppSettingsStore

    let settingsWindow: RegularWindow<SettingsView>
    let activationManager: ActivationManager

    @StateObject private var keyboard = KeyboardEventHandler()
    @State private var searchText = ""
    @State private var selectedIndex: Int = 0

    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let entries = SwitcherListLogic.filterEntries(
            editorStore: editorStore,
            projectRegistry: projectRegistry,
            appSettings: appSettings,
            searchText: searchText
        )

        VStack(spacing: Layout.listSpacing) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(GlassPalette.textSecondary(for: colorScheme))
                TextField("Search", text: $searchText)
                    .font(.system(size: Layout.searchFieldFontSize, weight: .medium))
                    .textFieldStyle(PlainTextFieldStyle())
                    .foregroundColor(GlassPalette.textPrimary(for: colorScheme))
                    .focused($focused)
                    .onChange(of: searchText) { _ in
                        selectedIndex = 0
                    }
            }
            .padding(.horizontal, 12)
            .frame(height: Layout.searchFieldHeight)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(GlassPalette.searchBackground(for: colorScheme))
            )

            ScrollView(.vertical) {
                VStack(spacing: Layout.listSpacing) {
                    ForEach(Array(entries.enumerated()), id: \.1.id) { index, entry in
                        Button(action: {
                            SwitcherListLogic.activateEntry(
                                at: index,
                                entries: entries,
                                selectedIndex: &selectedIndex,
                                editorStore: editorStore
                            )
                        }) {
                            HStack(spacing: 14) {
                                Group {
                                    if entry.isEditor {
                                        Image("EditorIcon")
                                            .resizable()
                                            .scaledToFit()
                                    } else {
                                        Image(systemName: entry.isStarred ? "star.circle.fill" : "folder.fill")
                                            .resizable()
                                            .scaledToFit()
                                    }
                                }
                                .frame(width: 18, height: 18)
                                .foregroundColor(
                                    entry.isEditor
                                        ? GlassPalette.textSecondary(for: colorScheme)
                                        : GlassPalette.projectTint
                                )
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.title)
                                        .font(.system(size: Layout.resultsFontSize, weight: .semibold))
                                        .foregroundColor(
                                            entry.isEditor
                                                ? GlassPalette.textPrimary(for: colorScheme)
                                                : GlassPalette.projectTint
                                        )
                                        .shadow(
                                            color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.08),
                                            radius: 1,
                                            x: 0,
                                            y: 1
                                        )
                                    Text(entry.displayPath)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(GlassPalette.textSecondary(for: colorScheme))
                                }
                                Spacer()
                                if let shortcut = shortcutLabel(for: index) {
                                    ShortcutPill(text: shortcut)
                                }
                                Image(systemName: "arrow.up.right.circle.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(
                                        selectedIndex == index
                                            ? (entry.isEditor ? GlassPalette.tint : GlassPalette.projectTint)
                                            : GlassPalette.textSecondary(for: colorScheme)
                                    )
                            }
                            .padding(.vertical, Layout.rowVerticalPadding)
                            .padding(.horizontal, Layout.rowHorizontalPadding)
                            .background(
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(
                                            selectedIndex == index
                                                ? (entry.isEditor
                                                    ? GlassPalette.rowSelected(for: colorScheme)
                                                    : GlassPalette.projectSelected(for: colorScheme))
                                                : GlassPalette.rowBackground(for: colorScheme)
                                        )
                                    if selectedIndex == index {
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(
                                                (entry.isEditor ? GlassPalette.tint : GlassPalette.projectTint)
                                                    .opacity(0.5),
                                                lineWidth: 1
                                            )
                                            .shadow(
                                                color: (entry.isEditor ? GlassPalette.tint : GlassPalette.projectTint)
                                                    .opacity(0.45),
                                                radius: 8,
                                                x: 0,
                                                y: 0
                                            )
                                            .blendMode(.screen)
                                    }
                                }
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(GlassPalette.stroke(for: colorScheme), lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .focusable(false)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: Layout.footerSpacing) {
                Spacer()
                GlassBottomBarButton(
                    text: "Quit Selected",
                    shortcut: ["⌘", "⌫"],
                    action: {
                        SwitcherListLogic.quitSelectedEditor(
                            entries: entries,
                            selectedIndex: &selectedIndex,
                            activationManager: activationManager
                        )
                    }
                )
                GlassBottomBarButton(
                    text: "Quit All",
                    shortcut: ["⌘", "Q"],
                    action: {
                        SwitcherListLogic.quitAllEditors(
                            editorStore: editorStore,
                            activationManager: activationManager
                        )
                    }
                )
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: selectedIndex)
        .onAppear {
            focused = true
            keyboard.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                MainThread.assert()
                return SwitcherListLogic.handleKey(
                    event,
                    editorStore: editorStore,
                    projectRegistry: projectRegistry,
                    appSettings: appSettings,
                    searchText: searchText,
                    selectedIndex: &selectedIndex,
                    switcherWindow: switcherWindow,
                    settingsWindow: settingsWindow,
                    activationManager: activationManager
                )
            }
        }
        .onDisappear {
            if let monitor = keyboard.monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}

struct GlassBottomBarButton: View {
    let text: String
    let shortcut: [Character]
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(text)
                    .foregroundColor(GlassPalette.textSecondary(for: colorScheme))
                HStack(spacing: 4) {
                    ForEach(shortcut, id: \.self) { key in
                        Text(String(key))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .font(.system(size: Layout.shortcutFontSize, design: .monospaced))
                            .foregroundColor(GlassPalette.textSecondary(for: colorScheme))
                            .background(GlassPalette.rowBackground(for: colorScheme))
                            .cornerRadius(4)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        hovering
                            ? GlassPalette.rowSelected(for: colorScheme)
                            : GlassPalette.rowBackground(for: colorScheme)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(GlassPalette.stroke(for: colorScheme), lineWidth: 1)
            )
        }
        .font(.system(size: Layout.footerFontSize, weight: .medium))
        .buttonStyle(PlainButtonStyle())
        .focusable(false)
        .onHover { isHovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                hovering = isHovering
            }
        }
    }
}

struct GlassPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GlassPrimaryButton(configuration: configuration)
    }
}

struct GlassGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GlassGhostButton(configuration: configuration)
    }
}

private struct GlassPrimaryButton: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(
                colorScheme == .dark
                    ? Color.black.opacity(configuration.isPressed ? 0.7 : 0.9)
                    : Color.black.opacity(configuration.isPressed ? 0.6 : 0.85)
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(GlassPalette.tint.opacity(colorScheme == .dark ? 0.95 : 0.85))
            .cornerRadius(10)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

private struct GlassGhostButton: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(GlassPalette.textPrimary(for: colorScheme))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(GlassPalette.rowBackground(for: colorScheme))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(GlassPalette.stroke(for: colorScheme), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

struct ShortcutPill: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.6))
            .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
            .cornerRadius(6)
    }
}

@MainActor
final class SwitcherWindowRef {
    private var window: SwitcherWindow?

    init(window: SwitcherWindow? = nil) {
        self.window = window
    }

    func set(_ window: SwitcherWindow) {
        self.window = window
    }

    func isSameWindow(_ window: NSWindow) -> Bool {
        if let win = self.window {
            return win.isSameWindow(window)
        } else {
            return false
        }
    }
}

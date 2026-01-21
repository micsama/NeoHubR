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

    static let commandNumberKeys: [UInt16] = [
        ONE, TWO, THREE, FOUR, FIVE, SIX, SEVEN, EIGHT, NINE
    ]
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

struct GlassPalette {
    static let tint = Color(red: 0.25, green: 0.82, blue: 0.82)

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

struct LegacyPalette {
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let rowSelected = Color.accentColor.opacity(0.12)
    static let border = Color.black.opacity(0.12)
    static let background = Color(NSColor.windowBackgroundColor).opacity(0.96)
    static let rowBackground = Color(NSColor.controlBackgroundColor).opacity(0.85)
}

struct LegacyBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Layout.windowCornerRadius)
            .fill(LegacyPalette.background)
            .overlay(
                RoundedRectangle(cornerRadius: Layout.windowCornerRadius)
                    .stroke(LegacyPalette.border, lineWidth: 1)
            )
    }
}

@available(macOS 26, *)
struct GlassBackgroundView: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.cornerRadius = Layout.windowCornerRadius
        return view
    }

    func updateNSView(_ nsView: NSGlassEffectView, context _: Context) {
        nsView.cornerRadius = Layout.windowCornerRadius
    }
}

@MainActor
final class SwitcherWindow: ObservableObject {
    private let editorStore: EditorStore
    private let settingsWindow: RegularWindow<SettingsView>
    private let selfRef: SwitcherWindowRef
    private let activationManager: ActivationManager
    private let appSettings: AppSettingsStore

    private var window: NSWindow!

    @Published private var hidden: Bool = true

    init(
        editorStore: EditorStore,
        settingsWindow: RegularWindow<SettingsView>,
        selfRef: SwitcherWindowRef,
        activationManager: ActivationManager,
        appSettings: AppSettingsStore
    ) {
        self.editorStore = editorStore
        self.settingsWindow = settingsWindow
        self.selfRef = selfRef
        self.activationManager = activationManager
        self.appSettings = appSettings

        let contentView = SwitcherView(
            editorStore: editorStore,
            switcherWindow: self,
            appSettings: appSettings,
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

        window.center()

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

        window.center()
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

    let settingsWindow: RegularWindow<SettingsView>
    let activationManager: ActivationManager

    private var state: SwitcherState? {
        if switcherWindow.isHidden() {
            return nil
        }

        let editors = editorStore.getEditors()

        switch editors.count {
        case 0:
            return .noEditors
        case 1:
            return .oneEditor
        default:
            return .manyEditors
        }
    }

    var body: some View {
        if appSettings.useGlassSwitcherUI {
            if #available(macOS 26, *) {
                GlassSwitcherRoot(
                    state: state,
                    editorStore: editorStore,
                    switcherWindow: switcherWindow,
                    settingsWindow: settingsWindow,
                    activationManager: activationManager
                )
            } else {
                LegacySwitcherRoot(
                    state: state,
                    editorStore: editorStore,
                    switcherWindow: switcherWindow,
                    settingsWindow: settingsWindow,
                    activationManager: activationManager
                )
            }
        } else {
            LegacySwitcherRoot(
                state: state,
                editorStore: editorStore,
                switcherWindow: switcherWindow,
                settingsWindow: settingsWindow,
                activationManager: activationManager
            )
        }
    }
}

struct LegacySwitcherRoot: View {
    let state: SwitcherState?
    @ObservedObject var editorStore: EditorStore
    @ObservedObject var switcherWindow: SwitcherWindow

    let settingsWindow: RegularWindow<SettingsView>
    let activationManager: ActivationManager

    var body: some View {
        ZStack {
            LegacyBackground()
            Group {
                switch state {
                case .noEditors:
                    LegacySwitcherEmptyView(
                        switcherWindow: switcherWindow,
                        settingsWindow: settingsWindow
                    )
                case .oneEditor, .manyEditors:
                    LegacySwitcherListView(
                        editorStore: editorStore,
                        switcherWindow: switcherWindow,
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

@available(macOS 26, *)
struct GlassSwitcherRoot: View {
    let state: SwitcherState?
    @ObservedObject var editorStore: EditorStore
    @ObservedObject var switcherWindow: SwitcherWindow

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

struct LegacySwitcherEmptyView: View {
    @ObservedObject var switcherWindow: SwitcherWindow

    let settingsWindow: RegularWindow<SettingsView>

    @StateObject private var keyboard = KeyboardEventHandler()
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(LegacyPalette.textSecondary)
            Text("No Neovide instances")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(LegacyPalette.textSecondary)
            HStack(spacing: 10) {
                Button("Settings") {
                    switcherWindow.hide()
                    settingsWindow.open()
                }
                Button("Close") { switcherWindow.hide() }
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

@available(macOS 26, *)
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

struct LegacySwitcherListView: View {
    @ObservedObject var editorStore: EditorStore
    @ObservedObject var switcherWindow: SwitcherWindow

    let settingsWindow: RegularWindow<SettingsView>
    let activationManager: ActivationManager

    @StateObject private var keyboard = KeyboardEventHandler()
    @State private var searchText = ""
    @State private var selectedIndex: Int = 0

    @FocusState private var focused: Bool

    var body: some View {
        let editors = filterEditors()

        VStack(spacing: Layout.listSpacing) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(LegacyPalette.textSecondary)
                TextField("Search", text: $searchText)
                    .font(.system(size: Layout.searchFieldFontSize))
                    .textFieldStyle(PlainTextFieldStyle())
                    .focused($focused)
                    .onChange(of: searchText) { _ in
                        selectedIndex = 0
                    }
            }
            .padding(.horizontal, 10)
            .frame(height: Layout.searchFieldHeight)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(LegacyPalette.rowBackground)
            )

            ScrollView(.vertical) {
                VStack(spacing: 4) {
                    ForEach(Array(editors.enumerated()), id: \.1.id) { index, editor in
                        Button(action: { editor.activate() }) {
                            HStack(spacing: 10) {
                                Image("EditorIcon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 16, height: 16)
                                    .foregroundColor(LegacyPalette.textSecondary)
                                Text(editor.name)
                                    .font(.system(size: Layout.resultsFontSize))
                                Spacer()
                                Text(editor.displayPath)
                                    .font(.system(size: 12))
                                    .foregroundColor(LegacyPalette.textSecondary)
                                if index < 9 {
                                    ShortcutPill(text: "⌘\(index + 1)")
                                }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedIndex == index ? LegacyPalette.rowSelected : Color.clear)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .focusable(false)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 10) {
                Spacer()
                Button("Quit Selected") { quitSelectedEditor() }
                Button("Quit All") { quitAllEditors() }
            }
            .font(.system(size: Layout.footerFontSize))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            focused = true
            keyboard.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                handleKey(event, editors: editors)
            }
        }
        .onDisappear {
            if let monitor = keyboard.monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }

    private func handleKey(_ event: NSEvent, editors: [Editor]) -> NSEvent? {
        switch event.keyCode {
        case Key.ARROW_UP:
            if selectedIndex > 0 {
                selectedIndex -= 1
            }
            return nil
        case Key.ARROW_DOWN:
            if selectedIndex < filterEditors().count - 1 {
                selectedIndex += 1
            }
            return nil
        case Key.TAB:
            selectedIndex = (selectedIndex + 1) % max(filterEditors().count, 1)
            return nil
        case Key.ENTER:
            if editors.indices.contains(selectedIndex) {
                let editor = editors[selectedIndex]
                editor.activate()
            }
            return nil
        case Key.BACKSPACE where event.modifierFlags.contains(.command):
            quitSelectedEditor()
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
            quitAllEditors()
            return nil
        case _ where event.modifierFlags.contains(.command):
            if let index = commandNumberIndex(for: event.keyCode) {
                activateEditor(at: index, editors: editors)
                return nil
            }
            return nil
        default:
            break
        }
        return event
    }

    private func filterEditors() -> [Editor] {
        editorStore.getEditors(sortedFor: .switcher).filter { editor in
            searchText.isEmpty
                || editor.name.contains(searchText)
                || editor.displayPath.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func quitSelectedEditor() {
        let editors = filterEditors()
        if editors.indices.contains(selectedIndex) {
            let editor = editors[selectedIndex]
            let totalEditors = editors.count

            if totalEditors == selectedIndex + 1 && selectedIndex != 0 {
                selectedIndex -= 1
            }

            if totalEditors == 1 {
                activationManager.activateTarget()
            }

            editor.quit()
        }
    }

    private func quitAllEditors() {
        Task {
            activationManager.activateTarget()
            await editorStore.quitAllEditors()
        }
    }

    private func activateEditor(at index: Int, editors: [Editor]) {
        guard editors.indices.contains(index) else {
            return
        }
        selectedIndex = index
        editors[index].activate()
    }

    private func commandNumberIndex(for keyCode: UInt16) -> Int? {
        guard let index = Key.commandNumberKeys.firstIndex(of: keyCode) else {
            return nil
        }
        return index
    }
}

@available(macOS 26, *)
struct GlassSwitcherListView: View {
    @ObservedObject var editorStore: EditorStore
    @ObservedObject var switcherWindow: SwitcherWindow

    let settingsWindow: RegularWindow<SettingsView>
    let activationManager: ActivationManager

    @StateObject private var keyboard = KeyboardEventHandler()
    @State private var searchText = ""
    @State private var selectedIndex: Int = 0

    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let editors = filterEditors()

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
                    ForEach(Array(editors.enumerated()), id: \.1.id) { index, editor in
                        Button(action: { editor.activate() }) {
                            HStack(spacing: 14) {
                                Image("EditorIcon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 18, height: 18)
                                    .foregroundColor(GlassPalette.textSecondary(for: colorScheme))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(editor.name)
                                        .font(.system(size: Layout.resultsFontSize, weight: .semibold))
                                        .foregroundColor(GlassPalette.textPrimary(for: colorScheme))
                                        .shadow(
                                            color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.08),
                                            radius: 1,
                                            x: 0,
                                            y: 1
                                        )
                                    Text(editor.displayPath)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(GlassPalette.textSecondary(for: colorScheme))
                                }
                                Spacer()
                                if index < 9 {
                                    ShortcutPill(text: "⌘\(index + 1)")
                                }
                                Image(systemName: "arrow.up.right.circle.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(
                                        selectedIndex == index
                                            ? GlassPalette.tint
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
                                                ? GlassPalette.rowSelected(for: colorScheme)
                                                : GlassPalette.rowBackground(for: colorScheme)
                                        )
                                    if selectedIndex == index {
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(GlassPalette.tint.opacity(0.5), lineWidth: 1)
                                            .shadow(color: GlassPalette.tint.opacity(0.45), radius: 8, x: 0, y: 0)
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
                GlassBottomBarButton(text: "Quit Selected", shortcut: ["⌘", "⌫"], action: { quitSelectedEditor() })
                GlassBottomBarButton(text: "Quit All", shortcut: ["⌘", "Q"], action: { quitAllEditors() })
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: selectedIndex)
        .onAppear {
            focused = true
            keyboard.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                handleKey(event, editors: editors)
            }
        }
        .onDisappear {
            if let monitor = keyboard.monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }

    private func handleKey(_ event: NSEvent, editors: [Editor]) -> NSEvent? {
        switch event.keyCode {
        case Key.ARROW_UP:
            if selectedIndex > 0 {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    selectedIndex -= 1
                }
            }
            return nil
        case Key.ARROW_DOWN:
            if selectedIndex < filterEditors().count - 1 {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    selectedIndex += 1
                }
            }
            return nil
        case Key.TAB:
            withAnimation(.spring(response: 0.26, dampingFraction: 0.78)) {
                selectedIndex = (selectedIndex + 1) % max(filterEditors().count, 1)
            }
            return nil
        case Key.ENTER:
            if editors.indices.contains(selectedIndex) {
                let editor = editors[selectedIndex]
                editor.activate()
            }
            return nil
        case Key.BACKSPACE where event.modifierFlags.contains(.command):
            quitSelectedEditor()
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
            quitAllEditors()
            return nil
        case _ where event.modifierFlags.contains(.command):
            if let index = commandNumberIndex(for: event.keyCode) {
                activateEditor(at: index, editors: editors)
                return nil
            }
            return nil
        default:
            break
        }
        return event
    }

    private func filterEditors() -> [Editor] {
        editorStore.getEditors(sortedFor: .switcher).filter { editor in
            searchText.isEmpty
                || editor.name.contains(searchText)
                || editor.displayPath.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func quitSelectedEditor() {
        let editors = filterEditors()
        if editors.indices.contains(selectedIndex) {
            let editor = editors[selectedIndex]
            let totalEditors = editors.count

            if totalEditors == selectedIndex + 1 && selectedIndex != 0 {
                selectedIndex -= 1
            }

            if totalEditors == 1 {
                activationManager.activateTarget()
            }

            editor.quit()
        }
    }

    private func quitAllEditors() {
        Task {
            activationManager.activateTarget()
            await editorStore.quitAllEditors()
        }
    }

    private func activateEditor(at index: Int, editors: [Editor]) {
        guard editors.indices.contains(index) else {
            return
        }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
            selectedIndex = index
        }
        editors[index].activate()
    }

    private func commandNumberIndex(for keyCode: UInt16) -> Int? {
        guard let index = Key.commandNumberKeys.firstIndex(of: keyCode) else {
            return nil
        }
        return index
    }
}

@available(macOS 26, *)
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

@available(macOS 26, *)
struct GlassPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GlassPrimaryButton(configuration: configuration)
    }
}

@available(macOS 26, *)
struct GlassGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GlassGhostButton(configuration: configuration)
    }
}

@available(macOS 26, *)
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

@available(macOS 26, *)
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

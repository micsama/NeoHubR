import AppKit
import KeyboardShortcuts
import NeoHubRLib
import SwiftUI

// MARK: - Model (Fully Cached)

@MainActor
struct SwitcherItem: Identifiable {
    let id: URL
    let entry: ProjectEntry
    let editor: Editor?
    let isStarred: Bool
    let isInvalid: Bool

    // 预计算属性，View 渲染时零开销
    let name: String
    let displayPath: String
    let isActive: Bool
    let isSession: Bool

    init(id: URL, entry: ProjectEntry, editor: Editor?, isStarred: Bool, isInvalid: Bool) {
        self.id = id
        self.entry = entry
        self.editor = editor
        self.isStarred = isStarred
        self.isInvalid = isInvalid
        self.isActive = editor != nil
        self.isSession = entry.isSession
        self.displayPath = ProjectPathFormatter.displayPath(entry.id)

        if let n = entry.name, !n.isEmpty {
            self.name = n
        } else {
            self.name =
                entry.isSession ? entry.id.deletingPathExtension().lastPathComponent : entry.id.lastPathComponent
        }
    }
}

// MARK: - ViewModel

@Observable
@MainActor
final class SwitcherViewModel {
    // Dependencies
    private let editorStore: EditorStore
    let projectRegistry: ProjectRegistryStore
    private let appSettings: AppSettingsStore
    private let activationManager: ActivationManager

    // Interaction Callbacks
    var onDismiss: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    // State
    var searchText = "" { didSet { resetSelectionIfNeeded() } }
    var selectedID: URL?
    private(set) var items: [SwitcherItem] = [] { didSet { resetSelectionIfNeeded() } }

    var switcherMaxItems: Int { appSettings.switcherMaxItems }

    init(
        editorStore: EditorStore, projectRegistry: ProjectRegistryStore, appSettings: AppSettingsStore,
        activationManager: ActivationManager
    ) {
        self.editorStore = editorStore
        self.projectRegistry = projectRegistry
        self.appSettings = appSettings
        self.activationManager = activationManager
    }

    // MARK: - Data Pipeline

    func refreshData() {
        projectRegistry.refreshValidity()
        let maxItems = AppSettings.clampSwitcherMaxItems(appSettings.switcherMaxItems)
        var newItems: [SwitcherItem] = []
        newItems.reserveCapacity(maxItems)

        // 1. 建立索引 (一次遍历完成)
        var registryIndex: [URL: (ProjectEntry, Bool)] = [:]
        for e in projectRegistry.starredEntries { registryIndex[ProjectRegistry.normalizeID(e.id)] = (e, true) }
        for e in projectRegistry.recentEntries { registryIndex[ProjectRegistry.normalizeID(e.id)] = (e, false) }

        var activeIDs: Set<URL> = []

        // 2. 添加活跃编辑器
        for editor in editorStore.getEditors(sortedFor: .switcher) where newItems.count < maxItems {
            let normalizedID = ProjectRegistry.normalizeID(editor.id.id)
            activeIDs.insert(normalizedID)

            let (entry, isStarred) =
                registryIndex[normalizedID] ?? (ProjectEntry(id: normalizedID, name: editor.name), false)

            newItems.append(
                SwitcherItem(
                    id: normalizedID, entry: entry, editor: editor, isStarred: isStarred, isInvalid: false
                ))
        }

        // 3. 补充非活跃项目 (Starred -> Recent)
        let sources: [(list: [ProjectEntry], isStarred: Bool)] = [
            (projectRegistry.starredEntries, true),
            (projectRegistry.recentEntries, false),
        ]

        for source in sources {
            for entry in source.list where newItems.count < maxItems {
                let normID = ProjectRegistry.normalizeID(entry.id)
                guard !activeIDs.contains(normID) else { continue }
                activeIDs.insert(normID)  // 防止 Starred 和 Recent 重复

                newItems.append(
                    SwitcherItem(
                        id: normID, entry: entry, editor: nil, isStarred: source.isStarred,
                        isInvalid: projectRegistry.isInvalid(entry)
                    ))
            }
        }

        items = newItems
    }

    var filteredEntries: [SwitcherItem] {
        if searchText.isEmpty { return items }
        return items.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.displayPath.localizedCaseInsensitiveContains(searchText)
        }
    }

    var isEmpty: Bool { editorStore.getEditors().isEmpty && projectRegistry.entries.isEmpty }

    // MARK: - Navigation & Actions

    func moveSelection(_ offset: Int) {
        let entries = filteredEntries
        guard !entries.isEmpty else { return }

        let currentIndex = entries.firstIndex(where: { $0.id == selectedID }) ?? -1
        // 巧妙利用模运算处理：wrap around logic
        let nextIndex = (currentIndex + offset + entries.count) % entries.count
        selectedID = entries[nextIndex].id
    }

    private func resetSelectionIfNeeded() {
        let filtered = filteredEntries
        if selectedID == nil || !filtered.contains(where: { $0.id == selectedID }) {
            selectedID = filtered.first?.id
        }
    }

    func activateSelected() {
        guard let id = selectedID, let item = filteredEntries.first(where: { $0.id == id }) else { return }
        activate(item)
    }

    func activate(at index: Int) {
        let entries = filteredEntries
        guard entries.indices.contains(index) else { return }
        let item = entries[index]
        selectedID = item.id
        activate(item)
    }

    private func activate(_ item: SwitcherItem) {
        item.editor?.activate() ?? editorStore.openProject(item.entry)
    }

    func quitSelected() {
        guard let id = selectedID, let idx = filteredEntries.firstIndex(where: { $0.id == id }) else { return }
        let item = filteredEntries[idx]
        guard let editor = item.editor else { return }

        // 智能光标移动
        if idx > 0 {
            selectedID = filteredEntries[idx - 1].id
        } else if filteredEntries.count > 1 {
            selectedID = filteredEntries[idx + 1].id
        }

        // 窗口焦点管理
        if filteredEntries.filter({ $0.isActive }).count == 1 { activationManager.activateTarget() }

        editor.quit()
        editorStore.removeEditor(id: editor.id)
        refreshData()
    }

    func quitAll() {
        onDismiss()
        activationManager.activateTarget()
        Task {
            await editorStore.quitAllEditors()
            await MainActor.run { refreshData() }
        }
    }
}

// MARK: - Window & Ref

@MainActor
final class SwitcherWindowRef {
    private weak var window: SwitcherWindow?
    func set(_ window: SwitcherWindow) { self.window = window }
    func isSameWindow(_ other: NSWindow) -> Bool { window?.isSameWindow(other) ?? false }
}

@MainActor
final class SwitcherWindow {
    private let panel: NSPanel
    private let viewModel: SwitcherViewModel
    private let activationManager: ActivationManager
    private let editorStore: EditorStore
    private let selfRef: SwitcherWindowRef

    init(
        editorStore: EditorStore, selfRef: SwitcherWindowRef, activationManager: ActivationManager,
        appSettings: AppSettingsStore, projectRegistry: ProjectRegistryStore
    ) {
        self.editorStore = editorStore
        self.selfRef = selfRef
        self.activationManager = activationManager
        self.viewModel = SwitcherViewModel(
            editorStore: editorStore, projectRegistry: projectRegistry, appSettings: appSettings,
            activationManager: activationManager)

        self.panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 380),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        selfRef.set(self)  // Bind immediately

        configurePanel()
        setupInteractions()

        panel.contentView = NSHostingView(rootView: SwitcherContentView(viewModel: viewModel))
    }

    private func configurePanel() {
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.setFrameAutosaveName(APP_NAME)
        [.closeButton, .miniaturizeButton, .zoomButton].forEach { panel.standardWindowButton($0)?.isHidden = true }
    }

    private func setupInteractions() {
        viewModel.onDismiss = { [weak self] in self?.hide() }
        viewModel.onOpenSettings = { [weak self] in
            self?.hide()
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        KeyboardShortcuts.onKeyDown(for: .toggleSwitcher) { [weak self] in self?.handleToggleSwitcher() }
        KeyboardShortcuts.onKeyDown(for: .toggleLastActiveEditor) { [weak self] in self?.handleToggleLastActive() }
    }

    // MARK: - Logic

    private func handleToggleSwitcher() {
        editorStore.pruneDeadEditors()
        panel.isVisible ? hide() : show()
    }

    private func handleToggleLastActive() {
        editorStore.pruneDeadEditors()
        guard let editor = editorStore.getEditors(sortedFor: .lastActiveEditor).first else {
            if !panel.isVisible { show() }
            return
        }

        let frontApp = NSWorkspace.shared.frontmostApplication
        if frontApp?.processIdentifier == editor.processIdentifier {
            NSRunningApplication(processIdentifier: editor.processIdentifier)?.hide()
        } else {
            if let app = frontApp {
                activationManager.setActivationTarget(currentApp: app, switcherWindow: selfRef, editors: [editor])
            }
            NSRunningApplication(processIdentifier: editor.processIdentifier)?.activate()
        }
    }

    private func show() {
        activationManager.setActivationTarget(
            currentApp: NSWorkspace.shared.frontmostApplication,
            switcherWindow: selfRef,
            editors: editorStore.getEditors()
        )
        viewModel.refreshData()  // 核心数据刷新点

        centerOnScreen()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == APP_BUNDLE_ID {
            activationManager.activateTarget()
        }
    }

    func isSameWindow(_ window: NSWindow) -> Bool { panel === window }

    private func centerOnScreen() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(
            NSPoint(
                x: frame.midX - panel.frame.width / 2,
                y: frame.midY - panel.frame.height / 2
            ))
    }
}

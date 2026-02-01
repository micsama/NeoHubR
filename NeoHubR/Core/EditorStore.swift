import AppKit
import KeyboardShortcuts
import NeoHubRLib
import Observation
import SwiftUI

@MainActor
@Observable
final class EditorStore {
    private var editors: [EditorID: Editor] = [:]

    let switcherWindow: SwitcherWindowRef
    let activationManager: ActivationManager
    let projectRegistry: ProjectRegistryStore
    private let activeEditorStore: ActiveEditorStore
    private let appSettings: AppSettingsStore

    private var restartPoller: Timer?

    init(
        activationManager: ActivationManager,
        switcherWindow: SwitcherWindowRef,
        projectRegistry: ProjectRegistryStore,
        appSettings: AppSettingsStore
    ) {
        self.switcherWindow = switcherWindow
        self.activationManager = activationManager
        self.projectRegistry = projectRegistry
        self.appSettings = appSettings
        self.activeEditorStore = ActiveEditorStore()

        KeyboardShortcuts.onKeyUp(for: .restartEditor) { [self] in
            self.restartActiveEditor()
        }
    }

    public enum SortTarget {
        case menubar
        case switcher
        case lastActiveEditor
    }

    public func getEditors() -> [Editor] {
        editors.values.map { $0 }
    }

    public func getEditors(sortedFor sortTarget: SortTarget) -> [Editor] {
        let editors = getEditors()

        switch sortTarget {
        case .menubar:
            return editors.sorted { $0.name > $1.name }
        case .lastActiveEditor:
            return editors.max(by: { $0.lastAcceessTime < $1.lastAcceessTime }).map { [$0] } ?? []
        case .switcher:
            var sorted = editors.sorted { $0.lastAcceessTime > $1.lastAcceessTime }

            if sorted.count > 1,
                case .neovide(let prevEditor) = activationManager.activationTarget,
                sorted.first?.processIdentifier == prevEditor.processIdentifier
            {
                sorted.swapAt(0, 1)
            }

            return sorted
        }
    }

    func runEditor(request: RunRequest) {
        let naming = EditorNamingPolicy.resolve(for: request)
        let sessionPath = ProjectRegistry.resolveSessionPath(
            workingDirectory: request.wd,
            path: request.path
        )
        let editorID = EditorID(naming.location)
        let editorName = naming.displayName
        updateProjectRegistry(location: naming.location, displayName: editorName, sessionPath: sessionPath)

        if let editor = editors[editorID] {
            log.info("Editor exists, activating: \(editorID)")
            activateEditor(editor)
            return
        }

        let currentApp = NSWorkspace.shared.frontmostApplication

        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }
            do {
                let process = try makeEditorProcess(request: request, sessionPath: sessionPath, editorID: editorID)
                try process.run()

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.handleProcessLaunch(
                        process: process,
                        request: request,
                        editorID: editorID,
                        editorName: editorName,
                        currentApp: currentApp
                    )
                }
            } catch {
                Task { @MainActor in
                    let error = ReportableError("Failed to run editor process", error: error)
                    log.error("\(error)")
                    NotificationManager.send(kind: .failedToRunEditorProcess, error: error)
                }
            }
        }
    }

    func activateEditor(_ editor: Editor) {
        if appSettings.enableNeovideIPC, let windowID = editor.ipcWindowID {
            Task { @MainActor in
                do {
                    try await NeovideIPCClient.activateWindow(id: windowID)
                    editor.recordAccess()
                } catch {
                    handleIPCFailureIfNeeded(error)
                    editor.activate()
                }
            }
            return
        }

        editor.activate()
    }

    nonisolated private func makeEditorProcess(
        request: RunRequest,
        sessionPath: URL?,
        editorID: EditorID,
        useIPC: Bool = false
    ) throws -> Process {
        let process = Process()
        process.executableURL = request.bin

        var args = request.opts
        if !args.contains("--no-fork") {
            args.append("--no-fork")
        }
        if useIPC && !args.contains("--neovide-ipc") {
            args.append("--neovide-ipc")
            args.append("unix:\(NeovideIPCClient.socketPath)")
        }
        if let sessionPath {
            if !args.contains("--") { args.append("--") }
            args.append("-S")
            args.append(sessionPath.path(percentEncoded: false))
        } else if let path = request.path {
            args.append(path)
        }
        process.arguments = args

        if let sessionPath {
            process.currentDirectoryURL = sessionPath.deletingLastPathComponent()
        } else {
            process.currentDirectoryURL = request.wd
        }
        var env = request.env
        env["LLVM_PROFILE_FILE"] = "/dev/null"
        process.environment = env

        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.editors.removeValue(forKey: editorID)
                self?.persistActiveEditors()
            }
        }
        return process
    }

    private func handleProcessLaunch(
        process: Process,
        request: RunRequest,
        editorID: EditorID,
        editorName: String,
        currentApp: NSRunningApplication?,
        ipcWindowID: String? = nil
    ) {
        activationManager.setActivationTarget(
            currentApp: currentApp,
            switcherWindow: switcherWindow,
            editors: getEditors()
        )

        if process.isRunning {
            log.info("Editor launched: \(editorID), pid \(process.processIdentifier)")

            editors[editorID] = Editor(
                id: editorID,
                name: editorName,
                process: process,
                request: request,
                ipcWindowID: ipcWindowID,
                onAccessed: { [weak self] in self?.persistActiveEditors() }
            )
            persistActiveEditors()
        } else {
            let error = ReportableError(
                "Editor process is not running",
                code: Int(process.terminationStatus),
                meta: [
                    "EditorID": editorID,
                    "EditorPID": process.processIdentifier,
                    "EditorTerminationStatus": process.terminationStatus,
                    "EditorWorkingDirectory": request.wd,
                    "EditorBinary": request.bin,
                    "EditorPathArgument": request.path ?? "-",
                    "EditorOptions": request.opts,
                ]
            )
            log.error("\(error)")
            NotificationManager.send(kind: .failedToRunEditorProcess, error: error)
        }
    }

    func restartActiveEditor() {
        guard let activeApp = NSWorkspace.shared.frontmostApplication,
            let editor = self.editors.first(where: { $0.value.processIdentifier == activeApp.processIdentifier })?.value
        else { return }

        editor.quit()

        let timeout: TimeInterval = 5
        let startTime = Date()
        let editorID = editor.id
        let editorRequest = editor.request

        self.restartPoller = Timer.scheduledTimer(withTimeInterval: 0.005, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if self.editors[editorID] == nil {
                    self.invalidateRestartPoller()
                    self.runEditor(request: editorRequest)
                } else if -startTime.timeIntervalSinceNow > timeout {
                    log.error("The editor wasn't removed from the store within the timeout. Canceling the restart.")
                    self.invalidateRestartPoller()
                    let error = ReportableError("Failed to restart the editor")
                    NotificationManager.send(kind: .failedToRestartEditor, error: error)
                }
            }
        }
    }

    func quitAllEditors() async {
        for editor in editors.values {
            editor.quit()
        }
        editors.removeAll()
        persistActiveEditors()
    }

    private func invalidateRestartPoller() {
        self.restartPoller?.invalidate()
    }

    func restoreActiveEditors() {
        let snapshots = activeEditorStore.loadSnapshots()
        guard !snapshots.isEmpty else { return }

        for snapshot in snapshots {
            guard let app = NSRunningApplication(processIdentifier: snapshot.pid), !app.isTerminated else { continue }

            let editorID = EditorID(snapshot.id)
            if editors[editorID] != nil { continue }

            editors[editorID] = Editor(
                id: editorID,
                name: snapshot.name,
                processIdentifier: snapshot.pid,
                request: snapshot.request,
                ipcWindowID: snapshot.ipcWindowID,
                lastAccessTime: Date(timeIntervalSince1970: snapshot.lastAccessTime),
                onAccessed: { [weak self] in self?.persistActiveEditors() }
            )
        }
        persistActiveEditors()
    }

    private func updateProjectRegistry(location: URL, displayName: String, sessionPath: URL?) {
        let projectID = sessionPath ?? location
        projectRegistry.touchRecent(root: projectID, name: displayName, sessionPath: sessionPath)
    }

    func openProject(_ project: ProjectEntry) {
        if projectRegistry.isInvalid(project) {
            NotificationManager.sendInfo(
                title: String(localized: "Project not accessible"),
                body: String(localized: "The project path is missing or not accessible.")
            )
            return
        }
        guard let bin = NeovideResolver.resolveBinary() else {
            let error = ReportableError("Failed to locate Neovide binary in PATH.")
            log.error("\(error)")
            NotificationManager.send(kind: .failedToRunEditorProcess, error: error)
            return
        }

        let targetURL = project.sessionPath ?? project.id
        let path = targetURL.path(percentEncoded: false)
        let wd = targetURL.hasDirectoryPath ? targetURL : targetURL.deletingLastPathComponent()

        let request = RunRequest(
            wd: wd,
            bin: bin,
            name: project.name,
            path: path,
            opts: [],
            env: ProcessInfo.processInfo.environment
        )
        runRequest(request)
    }

    func runRequest(_ request: RunRequest) {
        if appSettings.enableNeovideIPC {
            Task { @MainActor in
                await runOrActivateEditorWithIPC(request: request)
            }
        } else {
            runEditor(request: request)
        }
    }

    private func runOrActivateEditorWithIPC(request: RunRequest) async {
        let naming = EditorNamingPolicy.resolve(for: request)
        let sessionPath = ProjectRegistry.resolveSessionPath(
            workingDirectory: request.wd,
            path: request.path
        )
        let editorID = EditorID(naming.location)
        let editorName = naming.displayName
        updateProjectRegistry(location: naming.location, displayName: editorName, sessionPath: sessionPath)

        if let editor = editors[editorID] {
            if await activateEditorWithIPC(editor) { return }
            editors.removeValue(forKey: editorID)
            persistActiveEditors()
        }

        let nvimArgs = resolveIPCArgs(sessionPath: sessionPath, path: request.path)
        let existingWindowIDs = Set(editors.values.compactMap { $0.ipcWindowID })

        var createError: Error?
        do {
            if let windowID = try await NeovideIPCClient.createWindow(nvimArgs: nvimArgs) {
                registerIPCEditor(
                    editorID: editorID,
                    editorName: editorName,
                    request: request,
                    windowID: windowID
                )
                return
            }
        } catch {
            log.warning("IPC create window error: \(editorID) error=\(error)")
            createError = error
        }

        let currentApp = NSWorkspace.shared.frontmostApplication

        do {
            let process = try makeEditorProcess(
                request: request,
                sessionPath: sessionPath,
                editorID: editorID,
                useIPC: true
            )
            try process.run()
            handleProcessLaunch(
                process: process,
                request: request,
                editorID: editorID,
                editorName: editorName,
                currentApp: currentApp
            )

            guard process.isRunning else { return }
        } catch {
            let error = ReportableError("Failed to run editor process", error: error)
            log.error("\(error)")
            NotificationManager.send(kind: .failedToRunEditorProcess, error: error)
            return
        }

        do {
            try await Task.sleep(nanoseconds: NeovideIPCClient.Config.waitInitialDelayNanos)
            if let windowID = try await NeovideIPCClient.waitForNewWindowID(existingIDs: existingWindowIDs) {
                updateIPCWindowID(editorID: editorID, windowID: windowID)
                return
            }
        } catch {
            log.warning("IPC fallback wait error: \(editorID) error=\(error)")
            handleIPCFailureIfNeeded(error)
            return
        }

        log.error("IPC fallback failed to obtain window id: \(editorID)")
        handleIPCFailureIfNeeded(createError ?? NeovideIPCError.timeout)
    }

    private func activateEditorWithIPC(_ editor: Editor) async -> Bool {
        guard let windowID = editor.ipcWindowID else { return false }
        do {
            try await NeovideIPCClient.activateWindow(id: windowID)
            editor.recordAccess()
            return true
        } catch {
            handleIPCFailureIfNeeded(error)
            return false
        }
    }

    private func resolveIPCArgs(sessionPath: URL?, path: String?) -> [String] {
        if let sessionPath {
            return ["-S", sessionPath.path(percentEncoded: false)]
        }
        if let path { return [path] }
        return []
    }

    private func registerIPCEditor(
        editorID: EditorID,
        editorName: String,
        request: RunRequest,
        windowID: String
    ) {
        let pid = NeovideResolver.resolveRunningApplication()?.processIdentifier ?? 0
        activationManager.setActivationTarget(
            currentApp: NSWorkspace.shared.frontmostApplication,
            switcherWindow: switcherWindow,
            editors: getEditors()
        )

        if let editor = editors[editorID] {
            editor.updateIPCWindowID(windowID)
            editor.recordAccess()
        } else {
            editors[editorID] = Editor(
                id: editorID,
                name: editorName,
                processIdentifier: pid,
                request: request,
                ipcWindowID: windowID,
                onAccessed: { [weak self] in self?.persistActiveEditors() }
            )
        }
        persistActiveEditors()
    }

    private func updateIPCWindowID(editorID: EditorID, windowID: String) {
        if let editor = editors[editorID] {
            editor.updateIPCWindowID(windowID)
            persistActiveEditors()
        } else {
            log.warning("IPC update window id skipped (editor missing): \(editorID)")
        }
    }

    private func handleIPCFailureIfNeeded(_ error: Error) {
        let shouldClear: Bool
        let shouldNotify: Bool
        if let ipcError = error as? NeovideIPCError {
            switch ipcError {
            case .timeout:
                shouldClear = true
                shouldNotify = false
            case .invalidResponse, .serverError:
                shouldClear = false
                shouldNotify = true
            }
        } else {
            let isPosix = (error as NSError).domain == NSPOSIXErrorDomain
            shouldClear = isPosix
            shouldNotify = !isPosix
        }

        if shouldClear {
            editors.removeAll()
            persistActiveEditors()
        }

        if shouldNotify {
            let bodyKey: String.LocalizationValue = shouldClear
                ? "Neovide IPC is not responding. Editor list has been reset."
                : "Neovide IPC error. Please check logs."
            NotificationManager.sendInfo(
                title: String(localized: "Neovide IPC unavailable"),
                body: String(localized: bodyKey)
            )
        }
    }

    private func persistActiveEditors() {
        let snapshots = editors.values.map { editor in
            ActiveEditorSnapshot(
                id: editor.id.id,
                name: editor.name,
                pid: editor.processIdentifier,
                lastAccessTime: editor.lastAcceessTime.timeIntervalSince1970,
                request: editor.request,
                ipcWindowID: editor.ipcWindowID
            )
        }
        activeEditorStore.saveSnapshots(snapshots)
    }

    @MainActor
    deinit {
        self.invalidateRestartPoller()
    }
}

extension EditorStore {
    func pruneDeadEditors() {
        if appSettings.enableNeovideIPC {
            Task { @MainActor in
                await pruneDeadEditorsWithIPC()
            }
            return
        }

        let toRemove = editors.filter { _, editor in
            guard let app = NSRunningApplication(processIdentifier: editor.processIdentifier) else { return true }
            return app.isTerminated
        }

        if !toRemove.isEmpty {
            for (id, _) in toRemove {
                editors.removeValue(forKey: id)
            }
            persistActiveEditors()
        }
    }

    func removeEditor(id: EditorID) {
        editors.removeValue(forKey: id)
        persistActiveEditors()
    }

    func pruneDeadEditorsWithIPC() async {
        do {
            let ids = try await NeovideIPCClient.listWindows()
            let activeIDs = Set(ids)
            let toRemove = editors.filter { _, editor in
                guard let windowID = editor.ipcWindowID else { return false }
                return !activeIDs.contains(windowID)
            }

            if !toRemove.isEmpty {
                for (id, _) in toRemove {
                    editors.removeValue(forKey: id)
                }
                persistActiveEditors()
            }
        } catch {
            handleIPCFailureIfNeeded(error)
        }
    }
}

struct EditorID: Hashable, Identifiable, Sendable, CustomStringConvertible {
    private let loc: URL
    init(_ loc: URL) { self.loc = loc }
    var path: String { loc.path(percentEncoded: false) }
    var lastPathComponent: String { loc.lastPathComponent }
    var id: URL { self.loc }
    var description: String { self.path }
}

@MainActor
final class Editor: Identifiable {
    let id: EditorID
    let name: String

    private let process: Process?
    private let processIdentifierValue: Int32
    private let onAccessed: (() -> Void)?
    private(set) var lastAcceessTime: Date
    private(set) var request: RunRequest
    private(set) var ipcWindowID: String?

    init(
        id: EditorID,
        name: String,
        process: Process,
        request: RunRequest,
        ipcWindowID: String? = nil,
        onAccessed: (() -> Void)? = nil
    ) {
        self.id = id
        self.name = name
        self.process = process
        self.processIdentifierValue = process.processIdentifier
        self.lastAcceessTime = Date()
        self.request = request
        self.ipcWindowID = ipcWindowID
        self.onAccessed = onAccessed
    }

    init(
        id: EditorID,
        name: String,
        processIdentifier: Int32,
        request: RunRequest,
        ipcWindowID: String? = nil,
        lastAccessTime: Date = Date(),
        onAccessed: (() -> Void)? = nil
    ) {
        self.id = id
        self.name = name
        self.process = nil
        self.processIdentifierValue = processIdentifier
        self.lastAcceessTime = lastAccessTime
        self.request = request
        self.ipcWindowID = ipcWindowID
        self.onAccessed = onAccessed
    }

    var displayPath: String { ProjectPathFormatter.displayPath(self.id.path) }
    var processIdentifier: Int32 { self.processIdentifierValue }

    private func runningEditor() -> NSRunningApplication? {
        NSRunningApplication(processIdentifier: processIdentifierValue)
    }

    func activate() {
        guard let app = self.runningEditor() else {
            let error = ReportableError("Failed to get Neovide NSRunningApplication instance")
            log.error("\(error)")
            NotificationManager.send(kind: .failedToGetRunningEditorApp, error: error)
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        if !app.activate() {
            let error = ReportableError("Failed to activate Neovide instance")
            log.error("\(error)")
            NotificationManager.send(kind: .failedToActivateEditorApp, error: error)
        } else {
            recordAccess()
        }
    }

    func recordAccess() {
        self.lastAcceessTime = Date()
        self.onAccessed?()
    }

    func updateIPCWindowID(_ id: String?) {
        self.ipcWindowID = id
    }

    func quit() {
        if let process {
            process.terminate()
        } else {
            runningEditor()?.terminate()
        }
    }
}

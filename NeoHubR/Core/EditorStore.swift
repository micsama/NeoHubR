import AppKit
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

    init(
        activationManager: ActivationManager,
        switcherWindow: SwitcherWindowRef,
        projectRegistry: ProjectRegistryStore
    ) {
        self.switcherWindow = switcherWindow
        self.activationManager = activationManager
        self.projectRegistry = projectRegistry
        self.activeEditorStore = ActiveEditorStore()
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
            editor.activate()
            return
        }

        let currentApp = NSWorkspace.shared.frontmostApplication

        if AppSettings.useNeovideIPC {
            Task { @MainActor [weak self] in
                await self?.runEditorWithIPC(
                    request: request,
                    sessionPath: sessionPath,
                    editorID: editorID,
                    editorName: editorName,
                    currentApp: currentApp
                )
            }
            return
        }

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

    private func runEditorWithIPC(
        request: RunRequest,
        sessionPath: URL?,
        editorID: EditorID,
        editorName: String,
        currentApp: NSRunningApplication?
    ) async {
        activationManager.setActivationTarget(
            currentApp: currentApp,
            switcherWindow: switcherWindow,
            editors: getEditors()
        )

        let socketPath = AppSettings.neovideIPCSocketPath
        let nvimArgs = buildNvimArgs(sessionPath: sessionPath, request: request)

        do {
            let windowID = try await NeovideIPCClient.shared.createWindow(
                nvimArgs: nvimArgs,
                socketPath: socketPath
            )
            handleIPCWindowCreated(
                windowID: windowID,
                editorID: editorID,
                editorName: editorName,
                request: request
            )
        } catch {
            if case NeovideIPCError.connectionFailed = error {
                do {
                    try await autoStartNeovideWithIPC(request: request, sessionPath: sessionPath, socketPath: socketPath)
                    let windowID = try await waitForActiveWindowID(socketPath: socketPath)
                    handleIPCWindowCreated(
                        windowID: windowID,
                        editorID: editorID,
                        editorName: editorName,
                        request: request
                    )
                } catch {
                    let report = ReportableError("Failed to run editor via Neovide IPC", error: error)
                    log.error("\(report)")
                    NotificationManager.send(kind: .failedToRunEditorProcess, error: report)
                }
            } else {
                let report = ReportableError("Failed to run editor via Neovide IPC", error: error)
                log.error("\(report)")
                NotificationManager.send(kind: .failedToRunEditorProcess, error: report)
            }
        }
    }

    private func handleIPCWindowCreated(
        windowID: String,
        editorID: EditorID,
        editorName: String,
        request: RunRequest
    ) {
        editors[editorID] = Editor(
            id: editorID,
            name: editorName,
            windowID: windowID,
            request: request,
            onAccessed: { [weak self] in self?.persistActiveEditors() }
        )
        persistActiveEditors()
    }

    private func buildNvimArgs(sessionPath: URL?, request: RunRequest) -> [String] {
        if let sessionPath {
            return ["-S", sessionPath.path(percentEncoded: false)]
        }
        if let path = request.path {
            return [path]
        }
        return []
    }

    private func autoStartNeovideWithIPC(
        request: RunRequest,
        sessionPath: URL?,
        socketPath: String
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .background).async {
                do {
                    let process = Process()
                    process.executableURL = request.bin

                    var args = request.opts
                    if !args.contains("--no-fork") {
                        args.append("--no-fork")
                    }
                    if !args.contains("--neovide-ipc") {
                        args.append("--neovide-ipc")
                        args.append("unix:\(socketPath)")
                    }

                    if let sessionPath {
                        if !args.contains("--") { args.append("--") }
                        args.append("-S")
                        args.append(sessionPath.path(percentEncoded: false))
                    } else if let path = request.path {
                        args.append(path)
                    }

                    process.arguments = args
                    process.currentDirectoryURL = sessionPath?.deletingLastPathComponent() ?? request.wd
                    process.environment = request.env

                    try process.run()
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func waitForActiveWindowID(socketPath: String) async throws -> String {
        for _ in 0..<20 {
            do {
                let windows = try await NeovideIPCClient.shared.listWindows(socketPath: socketPath)
                if let active = windows.first(where: { $0.isActive == true }) {
                    return active.windowID
                }
                if let first = windows.first {
                    return first.windowID
                }
            } catch {
                try? await Task.sleep(nanoseconds: 200_000_000)
                continue
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        throw NeovideIPCError.noWindowsAvailable
    }

    nonisolated private func makeEditorProcess(request: RunRequest, sessionPath: URL?, editorID: EditorID) throws
        -> Process
    {
        let process = Process()
        process.executableURL = request.bin

        var args = request.opts
        if !args.contains("--no-fork") {
            args.append("--no-fork")
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
        process.environment = request.env

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
        currentApp: NSRunningApplication?
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


    func quitAllEditors() async {
        for editor in editors.values {
            editor.quit()
        }
        editors.removeAll()
        persistActiveEditors()
    }


    func restoreActiveEditors() {
        if AppSettings.useNeovideIPC {
            Task { @MainActor [weak self] in
                await self?.restoreActiveEditorsWithIPC()
            }
            return
        }

        let snapshots = activeEditorStore.loadSnapshots()
        guard !snapshots.isEmpty else { return }

        for snapshot in snapshots {
            guard let pid = snapshot.pid,
                let app = NSRunningApplication(processIdentifier: pid),
                !app.isTerminated
            else { continue }

            let editorID = EditorID(snapshot.id)
            if editors[editorID] != nil { continue }

            editors[editorID] = Editor(
                id: editorID,
                name: snapshot.name,
                processIdentifier: pid,
                request: snapshot.request,
                lastAccessTime: Date(timeIntervalSince1970: snapshot.lastAccessTime),
                onAccessed: { [weak self] in self?.persistActiveEditors() }
            )
        }
        persistActiveEditors()
    }

    private func restoreActiveEditorsWithIPC() async {
        let snapshots = activeEditorStore.loadSnapshots()
        guard !snapshots.isEmpty else { return }

        let socketPath = AppSettings.neovideIPCSocketPath
        let windows: [NeovideIPCWindow]
        do {
            windows = try await NeovideIPCClient.shared.listWindows(socketPath: socketPath)
        } catch {
            let report = ReportableError("Failed to list Neovide windows via IPC", error: error)
            log.error("\(report)")
            NotificationManager.send(kind: .failedToRunEditorProcess, error: report)
            return
        }

        let windowIDs = Set(windows.map { $0.windowID })
        for snapshot in snapshots {
            guard let windowID = snapshot.windowID, windowIDs.contains(windowID) else { continue }

            let editorID = EditorID(snapshot.id)
            if editors[editorID] != nil { continue }

            editors[editorID] = Editor(
                id: editorID,
                name: snapshot.name,
                windowID: windowID,
                request: snapshot.request,
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
        runEditor(request: request)
    }

    private func persistActiveEditors() {
        let snapshots = editors.values.map { editor in
            ActiveEditorSnapshot(
                id: editor.id.id,
                name: editor.name,
                pid: AppSettings.useNeovideIPC ? nil : editor.processIdentifier,
                windowID: AppSettings.useNeovideIPC ? editor.windowID : nil,
                lastAccessTime: editor.lastAcceessTime.timeIntervalSince1970,
                request: editor.request
            )
        }
        activeEditorStore.saveSnapshots(snapshots)
    }

    @MainActor
    deinit {}
}

extension EditorStore {
    func pruneDeadEditors() {
        if AppSettings.useNeovideIPC {
            Task { @MainActor [weak self] in
                await self?.pruneDeadEditorsWithIPC()
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

    private func pruneDeadEditorsWithIPC() async {
        let socketPath = AppSettings.neovideIPCSocketPath
        let windows: [NeovideIPCWindow]
        do {
            windows = try await NeovideIPCClient.shared.listWindows(socketPath: socketPath)
        } catch {
            let report = ReportableError("Failed to list Neovide windows via IPC", error: error)
            log.error("\(report)")
            NotificationManager.send(kind: .failedToRunEditorProcess, error: report)
            return
        }

        let windowIDs = Set(windows.map { $0.windowID })
        let toRemove = editors.filter { _, editor in
            guard let windowID = editor.windowID else { return true }
            return !windowIDs.contains(windowID)
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
    let windowID: String?

    private let process: Process?
    private let processIdentifierValue: Int32
    private let onAccessed: (() -> Void)?
    private(set) var lastAcceessTime: Date
    private(set) var request: RunRequest

    init(id: EditorID, name: String, process: Process, request: RunRequest, onAccessed: (() -> Void)? = nil) {
        self.id = id
        self.name = name
        self.windowID = nil
        self.process = process
        self.processIdentifierValue = process.processIdentifier
        self.lastAcceessTime = Date()
        self.request = request
        self.onAccessed = onAccessed
    }

    init(
        id: EditorID, name: String, processIdentifier: Int32, request: RunRequest, lastAccessTime: Date = Date(),
        onAccessed: (() -> Void)? = nil
    ) {
        self.id = id
        self.name = name
        self.windowID = nil
        self.process = nil
        self.processIdentifierValue = processIdentifier
        self.lastAcceessTime = lastAccessTime
        self.request = request
        self.onAccessed = onAccessed
    }

    init(
        id: EditorID, name: String, windowID: String, request: RunRequest, lastAccessTime: Date = Date(),
        onAccessed: (() -> Void)? = nil
    ) {
        self.id = id
        self.name = name
        self.windowID = windowID
        self.process = nil
        self.processIdentifierValue = 0
        self.lastAcceessTime = lastAccessTime
        self.request = request
        self.onAccessed = onAccessed
    }

    var displayPath: String { ProjectPathFormatter.displayPath(self.id.path) }
    var processIdentifier: Int32 { self.processIdentifierValue }

    private func runningEditor() -> NSRunningApplication? {
        NSRunningApplication(processIdentifier: processIdentifierValue)
    }

    func activate() {
        if AppSettings.useNeovideIPC, let windowID {
            Task {
                do {
                    _ = try await NeovideIPCClient.shared.activateWindow(
                        windowID,
                        socketPath: AppSettings.neovideIPCSocketPath
                    )
                    await MainActor.run {
                        self.lastAcceessTime = Date()
                        self.onAccessed?()
                    }
                } catch {
                    let report = ReportableError("Failed to activate Neovide window via IPC", error: error)
                    log.error("\(report)")
                    NotificationManager.send(kind: .failedToActivateEditorApp, error: report)
                }
            }
            return
        }

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
            self.lastAcceessTime = Date()
            self.onAccessed?()
        }
    }

    func quit() {
        if AppSettings.useNeovideIPC, windowID != nil {
            return
        }
        if let process {
            process.terminate()
        } else {
            runningEditor()?.terminate()
        }
    }
}

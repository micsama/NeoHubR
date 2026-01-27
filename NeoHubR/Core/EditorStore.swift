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

    private var restartPoller: Timer?

    init(
        activationManager: ActivationManager,
        switcherWindow: SwitcherWindowRef,
        projectRegistry: ProjectRegistryStore
    ) {
        self.switcherWindow = switcherWindow
        self.activationManager = activationManager
        self.projectRegistry = projectRegistry
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
        MainThread.assert()
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

        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }
            do {
                let process = try makeEditorProcess(request: request, sessionPath: sessionPath, editorID: editorID)
                try process.run()

                MainThread.run { [weak self] in
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
                MainThread.run {
                    let error = ReportableError("Failed to run editor process", error: error)
                    log.error("\(error)")
                    NotificationManager.send(kind: .failedToRunEditorProcess, error: error)
                }
            }
        }
    }

    nonisolated private func makeEditorProcess(request: RunRequest, sessionPath: URL?, editorID: EditorID) throws -> Process {
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

    func restartActiveEditor() {
        MainThread.assert()
        guard let activeApp = NSWorkspace.shared.frontmostApplication,
              let editor = self.editors.first(where: { $0.value.processIdentifier == activeApp.processIdentifier })?.value
        else { return }

        editor.quit()

        let timeout: TimeInterval = 5
        let startTime = Date()
        let editorID = editor.id
        let editorRequest = editor.request

        self.restartPoller = Timer.scheduledTimer(withTimeInterval: 0.005, repeats: true) { [weak self] _ in
            MainThread.run { [weak self] in
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
        MainThread.assert()
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
        MainThread.assert()
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
                pid: editor.processIdentifier,
                lastAccessTime: editor.lastAcceessTime.timeIntervalSince1970,
                request: editor.request
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

    init(id: EditorID, name: String, process: Process, request: RunRequest, onAccessed: (() -> Void)? = nil) {
        self.id = id
        self.name = name
        self.process = process
        self.processIdentifierValue = process.processIdentifier
        self.lastAcceessTime = Date()
        self.request = request
        self.onAccessed = onAccessed
    }

    init(id: EditorID, name: String, processIdentifier: Int32, request: RunRequest, lastAccessTime: Date = Date(), onAccessed: (() -> Void)? = nil) {
        self.id = id
        self.name = name
        self.process = nil
        self.processIdentifierValue = processIdentifier
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
        if let process {
            process.terminate()
        } else {
            runningEditor()?.terminate()
        }
    }
}
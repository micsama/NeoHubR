import AppKit
import KeyboardShortcuts
import NeoHubLib
import SwiftUI

@MainActor
final class EditorStore: ObservableObject {
    @Published private var editors: [EditorID: Editor]

    let switcherWindow: SwitcherWindowRef
    let activationManager: ActivationManager
    let projectRegistry: ProjectRegistryStore

    private var restartPoller: Timer?

    init(
        activationManager: ActivationManager,
        switcherWindow: SwitcherWindowRef,
        projectRegistry: ProjectRegistryStore
    ) {
        self.editors = [:]
        self.switcherWindow = switcherWindow
        self.activationManager = activationManager
        self.projectRegistry = projectRegistry

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
                let firstEditor = sorted.first,
                case .neovide(let prevEditor) = activationManager.activationTarget,
                firstEditor.processIdentifier == prevEditor.processIdentifier
            {
                // Swap the first editor with the second one
                // so it would require just Enter to switch between two editors
                sorted.swapAt(0, 1)
            }

            return sorted
        }
    }

    func runEditor(request: RunRequest) {
        MainThread.assert()
        let naming = EditorNamingPolicy.resolve(for: request)
        let editorID = EditorID(naming.location)
        let editorName = naming.displayName
        updateProjectRegistry(location: naming.location, displayName: editorName)

        switch editors[editorID] {
        case .some(let editor):
            log.info("Editor exists, activating: \(editorID)")
            editor.activate()
        case .none:
            let currentApp = NSWorkspace.shared.frontmostApplication

            DispatchQueue.global(qos: .background).async { [weak self] in
                guard let self else { return }
                do {
                    let process = Process()

                    process.executableURL = request.bin

                    let nofork = "--no-fork"

                    process.arguments = request.opts

                    if !process.arguments!.contains(nofork) {
                        process.arguments!.append(nofork)
                    }

                    if let path = request.path {
                        process.arguments!.append(path)
                    }

                    process.currentDirectoryURL = request.wd
                    process.environment = request.env

                    process.terminationHandler = { [editorID, self] _ in
                        Task { @MainActor in
                            self.editors.removeValue(forKey: editorID)
                        }
                    }

                    try process.run()

                    MainThread.run { [weak self] in
                        guard let self else { return }
                        self.activationManager.setActivationTarget(
                            currentApp: currentApp,
                            switcherWindow: self.switcherWindow,
                            editors: self.getEditors()
                        )

                        if process.isRunning {
                            log.info("Editor launched: \(editorID), pid \(process.processIdentifier)")

                            self.editors[editorID] = Editor(
                                id: editorID,
                                name: editorName,
                                process: process,
                                request: request
                            )
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
                } catch {
                    MainThread.run {
                        let error = ReportableError("Failed to run editor process", error: error)
                        log.error("\(error)")
                        NotificationManager.send(kind: .failedToRunEditorProcess, error: error)
                    }
                }
            }
        }
    }

    func restartActiveEditor() {
        MainThread.assert()
        guard let activeApp = NSWorkspace.shared.frontmostApplication else {
            return
        }

        guard
            let editor = self.editors.first(where: { id, editor in
                editor.processIdentifier == activeApp.processIdentifier
            })?.value
        else {
            return
        }

        editor.quit()

        let timeout = TimeInterval(5)
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

                    let alert = NSAlert()

                    alert.messageText = "Failed to restart the editor"
                    alert.informativeText = "Please, report the issue on GitHub."
                    alert.alertStyle = .critical
                    alert.addButton(withTitle: "Report")
                    alert.addButton(withTitle: "Dismiss")

                    switch alert.runModal() {
                    case .alertFirstButtonReturn:
                        let error = ReportableError("Failed to restart the editor")
                        BugReporter.report(error)
                    default: ()
                    }
                }
            }
        }
    }

    func quitAllEditors() async {
        MainThread.assert()
        for (_, editor) in self.editors {
            editor.quit()
        }
    }

    private func invalidateRestartPoller() {
        self.restartPoller?.invalidate()
    }

    private func updateProjectRegistry(location: URL, displayName: String) {
        var entries = projectRegistry.entries
        let now = Date()
        let normalizedLocation = ProjectRegistry.normalizeID(location)

        if let index = entries.firstIndex(where: { $0.id == normalizedLocation }) {
            var entry = entries[index]
            if (entry.name ?? "").isEmpty {
                entry.name = displayName
            }
            entry.lastOpenedAt = now
            entries[index] = entry
        } else {
            entries.append(ProjectEntry(id: normalizedLocation, name: displayName, lastOpenedAt: now))
        }

        entries.sort { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
        projectRegistry.entries = entries
    }

    func openProject(_ project: ProjectEntry) {
        guard let bin = resolveNeovideBinary() else {
            let error = ReportableError("Failed to locate Neovide binary in PATH.")
            log.error("\(error)")
            NotificationManager.send(kind: .failedToRunEditorProcess, error: error)
            return
        }

        let path = project.id.path(percentEncoded: false)
        let wd: URL
        if project.id.hasDirectoryPath {
            wd = project.id
        } else {
            wd = project.id.deletingLastPathComponent()
        }

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

    private func resolveNeovideBinary() -> URL? {
        if let path = resolveNeovideFromPath() {
            return path
        }

        let bundled = URL(fileURLWithPath: "/Applications/Neovide.app/Contents/MacOS/neovide")
        if FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }

        return nil
    }

    private func resolveNeovideFromPath() -> URL? {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", "neovide"]
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                return nil
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let path, !path.isEmpty else { return nil }
            return URL(fileURLWithPath: path)
        } catch {
            return nil
        }
    }

    @MainActor
    deinit {
        self.invalidateRestartPoller()
    }
}

struct EditorID: Hashable, Identifiable, Sendable, CustomStringConvertible {
    private let loc: URL

    init(_ loc: URL) {
        self.loc = loc
    }

    var path: String {
        loc.path(percentEncoded: false)
    }

    var lastPathComponent: String {
        loc.lastPathComponent
    }

    var id: URL { self.loc }

    var description: String { self.path }
}

@MainActor
final class Editor: Identifiable {
    let id: EditorID
    let name: String

    private let process: Process
    private(set) var lastAcceessTime: Date
    private(set) var request: RunRequest

    init(id: EditorID, name: String, process: Process, request: RunRequest) {
        self.id = id
        self.name = name
        self.process = process
        self.lastAcceessTime = Date()
        self.request = request
    }

    var displayPath: String {
        let fullPath = self.id.path
        let pattern = "^/Users/[^/]+/"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            log.warning("Invalid display path regular expression.")
            return fullPath
        }

        let range = NSRange(fullPath.startIndex..., in: fullPath)
        let result = regex.stringByReplacingMatches(
            in: fullPath,
            options: [],
            range: range,
            withTemplate: "~/"
        )

        return result
    }

    var processIdentifier: Int32 {
        self.process.processIdentifier
    }

    private func runningEditor() -> NSRunningApplication? {
        NSRunningApplication(processIdentifier: process.processIdentifier)
    }

    func activate() {
        guard let app = self.runningEditor() else {
            let error = ReportableError("Failed to get Neovide NSRunningApplication instance")
            log.error("\(error)")
            NotificationManager.send(kind: .failedToGetRunningEditorApp, error: error)
            return
        }

        // We have to activate NeoHub first so macOS would allow to activate Neovide
        NSApp.activate(ignoringOtherApps: true)

        let activated = app.activate()
        if !activated {
            let error = ReportableError("Failed to activate Neovide instance")
            log.error("\(error)")
            NotificationManager.send(kind: .failedToActivateEditorApp, error: error)
        } else {
            self.lastAcceessTime = Date()
        }
    }

    func quit() {
        process.terminate()
    }
}

import ArgumentParser
import Foundation
import NeoHubRLib

let APP_BUNDLE_ID = "com.micsama.NeoHubR.CLI"
let log = Logger.bootstrap(
    subsystem: APP_BUNDLE_ID,
    category: "cli",
    envVar: "NEOHUBR_LOG",
    alsoStderr: true
)

enum CLIError: Error, LocalizedError {
    case failedToGetBin
    case failedToCommunicateWithNeoHubR(SendError)
    case manual(String)

    var errorDescription: String? {
        switch self {
        case .failedToGetBin:
            return "Failed to get a path to Neovide binary. Make sure it is available in your PATH."
        case .failedToCommunicateWithNeoHubR(let error):
            return "Failed to communicate with NeoHubR: \(error.localizedDescription)"
        case .manual(let message):
            return message
        }
    }

    var report: CLIErrorReport {
        switch self {
        case .failedToGetBin:
            return CLIErrorReport(message: "Failed to get a path to Neovide binary.")
        case .failedToCommunicateWithNeoHubR(let error):
            return CLIErrorReport(message: "Failed to communicate with NeoHubR.", detail: error.localizedDescription)
        case .manual(let message):
            return CLIErrorReport(message: message)
        }
    }
}

@main
struct CLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "nh",
        abstract: "A CLI interface to NeoHubR. Launch new or activate already running Neovide instance.",
        version: "0.3.5"
    )

    @Argument(help: "Optional path passed to Neovide.")
    var path: String?

    @Option(help: "Optional editor name. Used for display only. If not provided, a file or directory name will be used.")
    var name: String?

    @Option(parsing: .remaining, help: "Options passed to Neovide")
    var opts: [String] = []

    @Option(help: "Send a CLI error message to the GUI for testing.")
    var error: String?

    mutating func run() async throws {
        if let error {
            await Self.sendErrorReport(.manual(error))
            throw CLIError.manual(error)
        }

        guard let bin = findNeovide() else {
            let error = CLIError.failedToGetBin
            await Self.sendErrorReport(error)
            throw error
        }

        let wd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let env = ProcessInfo.processInfo.environment
        
        let req = RunRequest(
            wd: wd,
            bin: bin,
            name: self.name,
            path: path.flatMap { $0.isEmpty ? nil : $0 },
            opts: self.opts,
            env: env
        )

        let result = await SocketClient().send(IPCMessage.run(req))

        switch result {
        case .success:
            return
        case .failure(let error):
            let cliError = CLIError.failedToCommunicateWithNeoHubR(error)
            await Self.sendErrorReport(cliError)
            throw cliError
        }
    }

    private func findNeovide() -> URL? {
        guard let pathEnv = ProcessInfo.processInfo.environment["PATH"] else { return nil }
        let paths = pathEnv.split(separator: ":")
        for path in paths {
            let url = URL(fileURLWithPath: String(path)).appendingPathComponent("neovide")
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private static func sendErrorReport(_ error: CLIError) async {
        let _ = await SocketClient().send(IPCMessage.cliError(error.report))
    }
}
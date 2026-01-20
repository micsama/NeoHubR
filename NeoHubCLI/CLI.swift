import ArgumentParser
import Foundation
import NeoHubLib

let APP_BUNDLE_ID = "com.alex35mil.NeoHub.CLI"

enum CLIError: Error {
    case failedToGetBin(Error)
    case failedToCommunicateWithNeoHub(SendError)
    case manual(String)
}

extension CLIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .failedToGetBin(let error):
            return
                """
                Failed to get a path to Neovide binary. Make sure it is available in your PATH.
                \(error.localizedDescription)
                """
        case .failedToCommunicateWithNeoHub(let error):
            return
                """
                Failed to communicate with NeoHub.
                \(error.localizedDescription)
                """
        case .manual(let message):
            return message
        }
    }
}

extension CLIError {
    var report: CLIErrorReport {
        switch self {
        case .failedToGetBin(let error):
            return CLIErrorReport(
                message: "Failed to get a path to Neovide binary.",
                detail: error.localizedDescription
            )
        case .failedToCommunicateWithNeoHub(let error):
            return CLIErrorReport(
                message: "Failed to communicate with NeoHub.",
                detail: error.localizedDescription
            )
        case .manual(let message):
            return CLIErrorReport(message: message)
        }
    }
}

@main
struct CLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "neohub",
        abstract: "A CLI interface to NeoHub. Launch new or activate already running Neovide instance.",
        version: "0.2.4f"
    )

    @Argument(help: "Optional path passed to Neovide.")
    var path: String?

    @Option(
        help: "Optional editor name. Used for display only. If not provided, a file or directory name will be used.")
    var name: String?

    @Option(parsing: .remaining, help: "Options passed to Neovide")
    var opts: [String] = []

    @Option(help: "Send a CLI error message to the GUI for testing.")
    var error: String?

    mutating func run() {
        if let error {
            Self.sendErrorReport(.manual(error))
            Self.exit(withError: CLIError.manual(error))
        }

        let wd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        let bin: URL
        switch Shell.run("command -v neovide") {
        case .success(let path):
            bin = URL(fileURLWithPath: path)
        case .failure(let error):
            Self.sendErrorReport(.failedToGetBin(error))
            Self.exit(withError: CLIError.failedToGetBin(error))
        }

        let path: String? =
            switch self.path {
            case nil, "": nil
            case .some(let path): .some(path)
            }

        let env = ProcessInfo.processInfo.environment

        let req = RunRequest(
            wd: wd,
            bin: bin,
            name: self.name,
            path: path,
            opts: self.opts,
            env: env
        )
        let message = IPCMessage.run(req)

        let client = SocketClient()
        let result = client.send(message)

        switch result {
        case .success(let res):
            Self.exit(withError: nil)
        case .failure(let error):
            Self.sendErrorReport(.failedToCommunicateWithNeoHub(error))
            Self.exit(withError: CLIError.failedToCommunicateWithNeoHub(error))
        }
    }

    private static func sendErrorReport(_ error: CLIError) {
        let message = IPCMessage.cliError(error.report)
        let _ = SocketClient().send(message)
    }
}

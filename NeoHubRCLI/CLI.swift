import ArgumentParser
import Darwin
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
    case manual(String)

    var errorDescription: String? {
        switch self {
        case .failedToGetBin:
            return "Failed to get a path to Neovide binary. Make sure it is available in your PATH."
        case .manual(let message):
            return message
        }
    }
}

@main
struct CLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "nh",
        abstract: "A CLI wrapper for launching Neovide.",
        version: "0.3.7"
    )

    @Argument(help: "Optional path passed to Neovide.")
    var path: String?

    @Option(parsing: .remaining, help: "Options passed to Neovide")
    var opts: [String] = []

    mutating func run() async throws {
        disableProfilingOutput()
        guard let bin = findNeovide() else {
            throw CLIError.failedToGetBin
        }

        var args = opts
        if let path, !path.isEmpty {
            args.append(path)
        }

        let process = Process()
        process.executableURL = bin
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                throw CLIError.manual("Neovide exited with status \(process.terminationStatus).")
            }
        } catch {
            if let cliError = error as? CLIError {
                throw cliError
            }
            throw CLIError.manual(error.localizedDescription)
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

    private func disableProfilingOutput() {
        setenv("LLVM_PROFILE_FILE", "/dev/null", 1)
    }
}

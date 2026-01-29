import AppKit
import Foundation
import Observation

private struct Bin {
    static let source = Bundle.main.bundlePath + "/Contents/SharedSupport/nh"
    static let destination = "/usr/local/bin/nh"
    static let legacySymlink = "/usr/local/bin/neohub"
}

enum CLIOperation {
    case install
    case uninstall
}

enum CLIStatus {
    case ok
    case error(reason: CLIError)
}

enum CLIError {
    case notInstalled
    case versionMismatch
    case unexpectedError(Error)
}

enum CLIInstallationError: Error {
    case failedToCreateAppleScript
    case userCanceledOperation
    case failedToExecuteAppleScript(message: String)
}

@MainActor
@Observable
final class CLI {
    private(set) var status: CLIStatus = .ok

    nonisolated static var binPath: String {
        Bin.destination
    }

    func refreshStatus() async -> CLIStatus {
        let status = await Task.detached {
            Self.getStatus()
        }.value

        self.status = status
        return status
    }

    nonisolated static func getStatus() -> CLIStatus {
        let fs = FileManager.default

        let installed = fs.fileExists(atPath: Bin.destination)

        if !installed {
            return .error(reason: .notInstalled)
        }

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(filePath: Bin.destination)
        process.arguments = ["--version"]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let output =
                    String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
                log.error("Failed to get CLI version. \(output)")
                return .error(
                    reason: .unexpectedError(
                        NSError(
                            domain: "CLI",
                            code: Int(process.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: output]
                        )))
            }

            let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let version =
                String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if version == APP_VERSION {
                return .ok
            }
            return .error(reason: .versionMismatch)
        } catch {
            log.error("Failed to get a CLI version. \(error)")
            return .error(reason: .unexpectedError(error))
        }
    }

    func run(_ operation: CLIOperation) async -> (Result<Void, CLIInstallationError>, CLIStatus) {
        let outcome = await Task.detached(priority: .background) {
            let script =
                switch operation {
                case .install:
                    "do shell script \"cp -f \(Bin.source) \(Bin.destination) && ln -sf \(Bin.destination) \(Bin.legacySymlink)\" with administrator privileges"
                case .uninstall:
                    "do shell script \"rm -f \(Bin.destination) \(Bin.legacySymlink)\" with administrator privileges"
                }
            let result = CLI.runAppleScript(script)
            let status = result.isSuccess ? CLI.getStatus() : nil
            return (result, status)
        }.value

        let status = outcome.1 ?? self.status
        self.status = status

        if outcome.0.isSuccess {
            switch operation {
            case .install:
                NotificationManager.sendInfo(
                    title: String(localized: "Boom!"),
                    body: String(localized: "The CLI is ready to roll 🚀")
                )
            case .uninstall:
                NotificationManager.sendInfo(
                    title: String(localized: "CLI Removed"),
                    body: String(localized: "The CLI has been removed.")
                )
            }
        }
        return (outcome.0, status)
    }

    nonisolated private static func runAppleScript(_ script: String) -> Result<Void, CLIInstallationError> {
        var error: NSDictionary?

        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)

            switch error {
            case .some(let error):
                if error["NSAppleScriptErrorNumber"] as? Int == -128 /* User canceled */ {
                    return .failure(.userCanceledOperation)
                } else {
                    let message = Self.formatAppleScriptError(error)
                    log.error("AppleScript failed: \(message)")
                    return .failure(.failedToExecuteAppleScript(message: message))
                }
            case .none:
                return .success(())
            }
        } else {
            return .failure(.failedToCreateAppleScript)
        }
    }

    nonisolated private static func formatAppleScriptError(_ error: NSDictionary) -> String {
        let message = (error["NSAppleScriptErrorMessage"] as? String) ?? "Unknown AppleScript error"
        let number = error["NSAppleScriptErrorNumber"] as? Int
        let range = error["NSAppleScriptErrorRange"]

        var parts = [message]
        if let number {
            parts.append("Code: \(number)")
        }
        if let range {
            parts.append("Range: \(String(describing: range))")
        }
        return parts.joined(separator: " | ")
    }

}

extension Result where Success == Void, Failure == CLIInstallationError {
    fileprivate var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }
}

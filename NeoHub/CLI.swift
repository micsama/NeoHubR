import AppKit
import Foundation

private struct Bin {
    static let source = Bundle.main.bundlePath + "/Contents/SharedSupport/neohub"
    static let destination = "/usr/local/bin/neohub"
}

private struct Lib {
    static let source = Bundle.main.bundlePath + "/Contents/Frameworks/NeoHubLib.framework"
    static let destination = "/usr/local/lib/NeoHubLib.framework"

    static var parent: String {
        return URL(fileURLWithPath: destination).deletingLastPathComponent().path
    }
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
    case failedToExecuteAppleScript(error: [String: String])
}

@MainActor
final class CLI: ObservableObject {
    @Published private(set) var status: CLIStatus = .ok

    func refreshStatus() async -> CLIStatus {
        let status = await Task.detached {
            Self.getStatus()
        }.value

        self.status = status
        return status
    }

    nonisolated static func getStatus() -> CLIStatus {
        let fs = FileManager.default

        let installed = fs.fileExists(atPath: Bin.destination) && fs.fileExists(atPath: Lib.destination)

        if !installed {
            return .error(reason: .notInstalled)
        }

        let version = Self.getVersion()

        switch version {
        case .success(let version):
            if version == APP_VERSION {
                return .ok
            } else {
                return .error(reason: .versionMismatch)
            }
        case .failure(let error):
            log.error("Failed to get a CLI version. \(error)")
            return .error(reason: .unexpectedError(error))
        }
    }

    func run(_ operation: CLIOperation) async -> (Result<Void, CLIInstallationError>, CLIStatus) {
        let outcome = await Task.detached(priority: .background) {
            let script =
                switch operation {
                case .install:
                    "do shell script \"mkdir -p \(Lib.parent) && cp -Rf \(Lib.source) \(Lib.destination) && cp -f \(Bin.source) \(Bin.destination)\" with administrator privileges"
                case .uninstall:
                    "do shell script \"rm \(Bin.destination) && rm -rf \(Lib.destination)\" with administrator privileges"
                }
            let result = CLI.runAppleScript(script)
            let status = result.isSuccess ? CLI.getStatus() : nil
            return (result, status)
        }.value

        let status = outcome.1 ?? self.status
        self.status = status
        return (outcome.0, status)
    }

    nonisolated private static func getVersion() -> Result<String, Error> {
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

            if process.terminationStatus == 0 {
                let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let result = String(data: data, encoding: .utf8)!.trimmingCharacters(in: .whitespacesAndNewlines)
                return .success(result)
            } else {
                let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = String(data: errorData, encoding: .utf8)!.trimmingCharacters(
                    in: .whitespacesAndNewlines)

                let error = ReportableError(
                    "Failed to get CLI version",
                    code: Int(process.terminationStatus),
                    meta: [
                        "StdErr": errorOutput.isEmpty ? "-" : errorOutput
                    ]
                )
                return .failure(error)
            }
        } catch {
            return .failure(error)
        }
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
                    return .failure(.failedToExecuteAppleScript(error: Self.normalizeAppleScriptError(error)))
                }
            case .none:
                return .success(())
            }
        } else {
            return .failure(.failedToCreateAppleScript)
        }
    }

    nonisolated private static func normalizeAppleScriptError(_ error: NSDictionary) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in error {
            if let key = key as? String {
                result[key] = String(describing: value)
            }
        }
        return result
    }
}

private extension Result where Success == Void, Failure == CLIInstallationError {
    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }
}

import Foundation
import NeoHubLib

private let envVar = "NEOHUB_LOG"
private let defaultLevel: LogLevel = .info

struct CLILogger: Sendable {
    private let logger: AppLogger

    init(logger: AppLogger) {
        self.logger = logger
    }

    func trace(_ message: String) {
        logger.trace(message)
    }

    func debug(_ message: String) {
        logger.debug(message)
    }

    func info(_ message: String) {
        logger.info(message)
    }

    func warning(_ message: String) {
        logger.warning(message)
    }

    func error(_ message: String) {
        logger.error(message)
        writeToStderr(message)
    }

    func critical(_ message: String) {
        logger.critical(message)
        writeToStderr(message)
    }
}

private func writeToStderr(_ message: String) {
    fputs("\(message)\n", stderr)
}

private func parseLogLevel(_ value: String) -> LogLevel? {
    switch value.lowercased() {
    case "trace": return .trace
    case "debug": return .debug
    case "info": return .info
    case "warn", "warning": return .warning
    case "error": return .error
    case "critical", "fault": return .critical
    default: return nil
    }
}

private func bootstrapLogger() -> CLILogger {
    let level =
        switch ProcessInfo.processInfo.environment[envVar] {
        case .some(let value): parseLogLevel(value) ?? defaultLevel
        case .none: defaultLevel
        }

    let logger = AppLogger(subsystem: APP_BUNDLE_ID, category: "cli", level: level)
    return CLILogger(logger: logger)
}

let log = bootstrapLogger()

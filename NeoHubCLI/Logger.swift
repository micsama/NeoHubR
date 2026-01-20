import Foundation
import os

private let envVar = "NEOHUB_LOG"
private let defaultLevel: LogLevel = .info

enum LogLevel: Int {
    case trace = 0
    case debug = 1
    case info = 2
    case warning = 3
    case error = 4
    case critical = 5
}

struct AppLogger {
    private let logger: Logger
    private let level: LogLevel

    init(subsystem: String, category: String, level: LogLevel) {
        self.logger = Logger(subsystem: subsystem, category: category)
        self.level = level
    }

    private func shouldLog(_ messageLevel: LogLevel) -> Bool {
        messageLevel.rawValue >= level.rawValue
    }

    func trace(_ message: String) {
        guard shouldLog(.trace) else { return }
        logger.debug("\(message, privacy: .public)")
    }

    func debug(_ message: String) {
        guard shouldLog(.debug) else { return }
        logger.debug("\(message, privacy: .public)")
    }

    func info(_ message: String) {
        guard shouldLog(.info) else { return }
        logger.info("\(message, privacy: .public)")
    }

    func warning(_ message: String) {
        guard shouldLog(.warning) else { return }
        logger.notice("\(message, privacy: .public)")
    }

    func error(_ message: String) {
        guard shouldLog(.error) else { return }
        logger.error("\(message, privacy: .public)")
    }

    func critical(_ message: String) {
        guard shouldLog(.critical) else { return }
        logger.fault("\(message, privacy: .public)")
    }
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

private func bootstrapLogger() -> AppLogger {
    let level =
    switch ProcessInfo.processInfo.environment[envVar] {
        case .some(let value): parseLogLevel(value) ?? defaultLevel
        case .none: defaultLevel
    }

    return AppLogger(subsystem: APP_BUNDLE_ID, category: "cli", level: level)
}

let log = bootstrapLogger()

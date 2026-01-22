import Foundation
import os

public enum LogLevel: Int, Sendable {
    case trace = 0
    case debug = 1
    case info = 2
    case warning = 3
    case error = 4
    case critical = 5

    public static func parse(_ value: String) -> LogLevel? {
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
}

public struct Logger: Sendable {
    private let logger: os.Logger
    private let level: LogLevel
    private let alsoStderr: Bool

    public init(subsystem: String, category: String, level: LogLevel, alsoStderr: Bool) {
        self.logger = os.Logger(subsystem: subsystem, category: category)
        self.level = level
        self.alsoStderr = alsoStderr
    }

    public static func bootstrap(
        subsystem: String,
        category: String,
        defaultLevel: LogLevel = .info,
        envVar: String? = nil,
        alsoStderr: Bool = false
    ) -> Logger {
        let level = resolvedLevel(envVar: envVar, defaultLevel: defaultLevel)
        return Logger(subsystem: subsystem, category: category, level: level, alsoStderr: alsoStderr)
    }

    private func shouldLog(_ messageLevel: LogLevel) -> Bool {
        messageLevel.rawValue >= level.rawValue
    }

    public func trace(_ message: String) {
        guard shouldLog(.trace) else { return }
        logger.debug("\(message, privacy: .public)")
    }

    public func debug(_ message: String) {
        guard shouldLog(.debug) else { return }
        logger.debug("\(message, privacy: .public)")
    }

    public func info(_ message: String) {
        guard shouldLog(.info) else { return }
        logger.info("\(message, privacy: .public)")
    }

    public func warning(_ message: String) {
        guard shouldLog(.warning) else { return }
        logger.notice("\(message, privacy: .public)")
    }

    public func notice(_ message: String) {
        guard shouldLog(.warning) else { return }
        logger.notice("\(message, privacy: .public)")
    }

    public func error(_ message: String) {
        guard shouldLog(.error) else { return }
        logger.error("\(message, privacy: .public)")
        if alsoStderr { writeToStderr(message) }
    }

    public func critical(_ message: String) {
        guard shouldLog(.critical) else { return }
        logger.fault("\(message, privacy: .public)")
        if alsoStderr { writeToStderr(message) }
    }
}

private func resolvedLevel(envVar: String?, defaultLevel: LogLevel) -> LogLevel {
    guard let envVar else { return defaultLevel }
    guard let value = ProcessInfo.processInfo.environment[envVar],
          let parsed = LogLevel.parse(value) else {
        return defaultLevel
    }
    return parsed
}

private func writeToStderr(_ message: String) {
    fputs("\(message)\n", stderr)
}

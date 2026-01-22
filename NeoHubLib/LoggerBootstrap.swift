import Foundation

public struct CLILogger: Sendable {
    private let logger: AppLogger
    private let alsoStderr: Bool

    public init(logger: AppLogger, alsoStderr: Bool) {
        self.logger = logger
        self.alsoStderr = alsoStderr
    }

    public func trace(_ message: String) {
        logger.trace(message)
    }

    public func debug(_ message: String) {
        logger.debug(message)
    }

    public func info(_ message: String) {
        logger.info(message)
    }

    public func warning(_ message: String) {
        logger.warning(message)
    }

    public func error(_ message: String) {
        logger.error(message)
        if alsoStderr { writeToStderr(message) }
    }

    public func critical(_ message: String) {
        logger.critical(message)
        if alsoStderr { writeToStderr(message) }
    }
}

public func bootstrapAppLogger(
    subsystem: String,
    category: String,
    defaultLevel: LogLevel
) -> AppLogger {
    AppLogger(subsystem: subsystem, category: category, level: defaultLevel)
}

public func bootstrapCLILogger(
    subsystem: String,
    category: String,
    envVar: String = "NEOHUB_LOG",
    defaultLevel: LogLevel = .info,
    alsoStderr: Bool = true
) -> CLILogger {
    let level: LogLevel
    if let value = ProcessInfo.processInfo.environment[envVar],
       let parsed = parseLogLevel(value) {
        level = parsed
    } else {
        level = defaultLevel
    }

    let logger = AppLogger(subsystem: subsystem, category: category, level: level)
    return CLILogger(logger: logger, alsoStderr: alsoStderr)
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

private func writeToStderr(_ message: String) {
    fputs("\(message)\n", stderr)
}

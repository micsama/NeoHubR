import os

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

    func notice(_ message: String) {
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

private let defaultLevel: LogLevel = {
    #if DEBUG
        return .debug
    #else
        return .info
    #endif
}()

let log = AppLogger(subsystem: APP_BUNDLE_ID, category: "app", level: defaultLevel)

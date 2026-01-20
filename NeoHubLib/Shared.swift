import Foundation
import os

public struct Socket {
    public static let addr = "/tmp/neohub.sock"
}

public struct RunRequest: Codable, Sendable {
    public let wd: URL
    public let bin: URL
    public let name: String?
    public let path: String?
    public let opts: [String]
    public let env: [String: String]

    public init(
        wd: URL,
        bin: URL,
        name: String?,
        path: String?,
        opts: [String],
        env: [String: String]
    ) {
        self.wd = wd
        self.bin = bin
        self.name = name
        self.path = path
        self.opts = opts
        self.env = env
    }
}

public struct CLIErrorReport: Codable, Sendable {
    public let message: String
    public let detail: String?
    public let code: Int?

    public init(message: String, detail: String? = nil, code: Int? = nil) {
        self.message = message
        self.detail = detail
        self.code = code
    }
}

public enum IPCMessageType: String, Codable, Sendable {
    case run
    case cliError
}

public struct IPCMessage: Codable, Sendable {
    public let type: IPCMessageType
    public let run: RunRequest?
    public let cliError: CLIErrorReport?

    private init(type: IPCMessageType, run: RunRequest?, cliError: CLIErrorReport?) {
        self.type = type
        self.run = run
        self.cliError = cliError
    }

    public static func run(_ request: RunRequest) -> IPCMessage {
        IPCMessage(type: .run, run: request, cliError: nil)
    }

    public static func cliError(_ report: CLIErrorReport) -> IPCMessage {
        IPCMessage(type: .cliError, run: nil, cliError: report)
    }
}

public enum LogLevel: Int, Sendable {
    case trace = 0
    case debug = 1
    case info = 2
    case warning = 3
    case error = 4
    case critical = 5
}

public struct AppLogger: Sendable {
    private let logger: Logger
    private let level: LogLevel

    public init(subsystem: String, category: String, level: LogLevel) {
        self.logger = Logger(subsystem: subsystem, category: category)
        self.level = level
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
    }

    public func critical(_ message: String) {
        guard shouldLog(.critical) else { return }
        logger.fault("\(message, privacy: .public)")
    }
}

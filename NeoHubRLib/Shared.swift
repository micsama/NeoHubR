import Foundation

public struct Socket {
    public static let addr = "/tmp/neohubr.sock"
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

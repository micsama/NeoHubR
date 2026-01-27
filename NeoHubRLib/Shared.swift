import Foundation

public struct Socket {
    public static var addr: String {
        "/tmp/neohubr-\(getuid()).sock"
    }
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

public enum PathUtils {
    public static func expandTilde(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    public static func normalize(_ url: URL) -> URL {
        let expandedPath = expandTilde(url.path(percentEncoded: false))
        let trimmedPath = trimTrailingSlash(expandedPath)
        var normalized = URL(fileURLWithPath: trimmedPath).standardizedFileURL

        if FileManager.default.fileExists(atPath: normalized.path) {
            normalized = normalized.resolvingSymlinksInPath()
        }

        if let isCaseSensitive = isCaseSensitiveVolume(for: normalized), !isCaseSensitive {
            normalized = URL(fileURLWithPath: normalized.path.lowercased())
        }

        return normalized
    }

    public static func normalizeSessionPath(_ url: URL) -> URL {
        let standardized = url.standardizedFileURL
        if FileManager.default.fileExists(atPath: standardized.path) {
            return standardized.resolvingSymlinksInPath()
        }
        return standardized
    }

    public static func isAccessible(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return false
        }
        if isDirectory.boolValue {
            return FileManager.default.isReadableFile(atPath: path) && FileManager.default.isExecutableFile(atPath: path)
        }
        return FileManager.default.isReadableFile(atPath: path)
    }

    private static func trimTrailingSlash(_ path: String) -> String {
        guard path.count > 1 else { return path }
        var result = path
        while result.hasSuffix("/") && result.count > 1 {
            result.removeLast()
        }
        return result
    }

    private static func isCaseSensitiveVolume(for url: URL) -> Bool? {
        try? url.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]).volumeSupportsCaseSensitiveNames
    }
}

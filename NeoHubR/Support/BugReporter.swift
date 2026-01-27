import AppKit
import Foundation

private struct GitHub {
    static let user = "micsama"
    static let repo = "NeoHubR"
}

struct BugReporter {
    static func report(_ error: ReportableError) {
        openIssue(title: error.message, body: buildBody(for: error))
    }

    static func report(title: String, error: String) {
        openIssue(title: title, body: buildBody(for: error))
    }

    private static func openIssue(title: String, body: String) {
        var components = URLComponents(string: "https://github.com/\(GitHub.user)/\(GitHub.repo)/issues/new")
        components?.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "body", value: body),
            URLQueryItem(name: "labels", value: "user-report"),
        ]

        if let url = components?.url {
            NSWorkspace.shared.open(url)
        } else {
            log.warning("Failed to create the reporter url")
        }
    }

    private static func buildBody(for error: Any) -> String {
        """
        ## What happened?
        _Reproduction steps, context, etc._

        ## Error details
        ```
        \(String(describing: error))
        ```
        """
    }
}

struct ReportableError: Error {
    private(set) var message: String
    private let appVersion: String
    private let appBuild: String
    private let code: Int?
    private(set) var context: String
    private var meta: [String: String]?
    private let osVersion: String
    private let arch: String?
    private let originalError: Error?

    init(
        _ message: String,
        code: Int? = nil,
        meta: [String: Any]? = nil,
        file: NSString = #file,
        function: NSString = #function,
        error: Error? = nil
    ) {
        if let error, var reportableError = error as? Self {
            if message != reportableError.message {
                reportableError.message = "\(message) → \(reportableError.message)"
            }

            let context = Self.buildContext(from: (file: file, function: function))

            if context != reportableError.context {
                reportableError.context = "\(context) → \(reportableError.context)"
            }

            switch (meta, reportableError.meta) {
            case (.some(let meta), .none):
                reportableError.meta = Self.normalizeMeta(meta)
            case (.some(let meta), .some(var reportableErrorMeta)):
                reportableErrorMeta.merge(Self.normalizeMeta(meta)) { c, _ in c }
                reportableError.meta = reportableErrorMeta
            case (.none, .some(_)),
                (.none, .none):
                ()
            }

            self = reportableError
        } else {
            self.message = message
            self.appVersion = APP_VERSION
            self.appBuild = APP_BUILD
            self.osVersion = ProcessInfo.processInfo.operatingSystemVersionString
            self.arch = Self.getSystemArch()
            self.code = code
            self.context = Self.buildContext(from: (file: file, function: function))
            self.originalError = error

            switch (meta, error.flatMap { err in err as NSError }) {
            case (.some(let meta), .some(let nsError)) where !nsError.userInfo.isEmpty:
                var merged = Self.normalizeMeta(meta)
                merged.merge(Self.normalizeUserInfo(nsError.userInfo)) { c, _ in c }
                self.meta = merged
            case (.some(let meta), _):
                self.meta = Self.normalizeMeta(meta)
            case (.none, .some(let nsError)) where !nsError.userInfo.isEmpty:
                self.meta = Self.normalizeUserInfo(nsError.userInfo)
            case (.none, _):
                self.meta = nil
            }
        }
    }

    var localizedDescription: String {
        String(describing: self)
    }

    private static func buildContext(from loc: (file: NSString, function: NSString)) -> String {
        "\((loc.file.lastPathComponent as NSString).deletingPathExtension)#\(loc.function)"
    }

    private static func normalizeMeta(_ meta: [String: Any]) -> [String: String] {
        meta.mapValues { String(describing: $0) }
    }

    private static func normalizeUserInfo(_ userInfo: [String: Any]) -> [String: String] {
        userInfo.mapValues { String(describing: $0) }
    }

    private static func getSystemArch() -> String? {
        var sysinfo = utsname()

        uname(&sysinfo)

        let data = Data(bytes: &sysinfo.machine, count: Int(_SYS_NAMELEN))

        return String(bytes: data, encoding: .ascii)?.trimmingCharacters(in: .controlCharacters)
    }
}

extension ReportableError: CustomStringConvertible {
    var description: String {
        var output =
            """
            \(message)
            App: Version \(appVersion) (Build \(appBuild))
            macOS: \(osVersion)
            Arch: \(arch ?? "?")
            Context: \(context)
            """

        if let code {
            output.append("\n")
            output.append("Code: \(code)")
        }

        if let error = originalError {
            output.append("\n")
            output.append("Original Error: \(error)")
        }

        if let meta, !meta.isEmpty {
            output.append(
                """

                Metadata:
                    \(meta.debugDescription)
                """
            )
        }

        return output
    }
}

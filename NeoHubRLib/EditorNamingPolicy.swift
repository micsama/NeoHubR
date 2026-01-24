import Foundation

public enum EditorNamingPolicy {
    public struct Result: Sendable {
        public let location: URL
        public let displayName: String

        public init(location: URL, displayName: String) {
            self.location = location
            self.displayName = displayName
        }
    }

    public static func resolve(for request: RunRequest) -> Result {
        let location = resolveLocation(workingDirectory: request.wd, path: request.path)
        let displayName = resolveDisplayName(explicitName: request.name, location: location)
        return Result(location: location, displayName: displayName)
    }

    public static func resolveLocation(workingDirectory: URL, path: String?) -> URL {
        switch path {
        case nil, "":
            return workingDirectory
        case .some(let path):
            if path.hasPrefix("/") {
                return URL(fileURLWithPath: path)
            }
            return workingDirectory.appendingPathComponent(path)
        }
    }

    public static func resolveDisplayName(explicitName: String?, location: URL) -> String {
        switch explicitName {
        case nil, "":
            location.lastPathComponent
        case .some(let name):
            name
        }
    }
}

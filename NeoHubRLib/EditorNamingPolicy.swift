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
            return workingDirectory.standardizedFileURL
        case .some(let path):
            let rawURL: URL
            if path.hasPrefix("~") {
                let expanded = (path as NSString).expandingTildeInPath
                rawURL = URL(fileURLWithPath: expanded)
            } else if path.hasPrefix("/") {
                rawURL = URL(fileURLWithPath: path)
            } else {
                rawURL = workingDirectory.appendingPathComponent(path)
            }
            if rawURL.pathExtension.lowercased() == "vim" {
                return rawURL.standardizedFileURL
            }
            return resolveProjectRoot(candidate: rawURL)
        }
    }

    public static func resolveDisplayName(explicitName: String?, location: URL) -> String {
        switch explicitName {
        case nil, "":
            if location.pathExtension.lowercased() == "vim" {
                let parentName = location.deletingLastPathComponent().lastPathComponent
                if !parentName.isEmpty {
                    return parentName
                }
                return location.deletingPathExtension().lastPathComponent
            }
            return location.lastPathComponent
        case .some(let name):
            return name
        }
    }

    private static func resolveProjectRoot(candidate: URL) -> URL {
        let standardized = candidate.standardizedFileURL
        let path = standardized.path(percentEncoded: false)
        var isDirectory: ObjCBool = false

        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                return standardized
            }
            return standardized.deletingLastPathComponent()
        }

        return standardized.deletingLastPathComponent()
    }
}

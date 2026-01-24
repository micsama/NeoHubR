import Foundation
import Observation

public struct ProjectEntry: Identifiable, Codable, Hashable, Sendable {
    public let id: URL
    public var name: String?
    public var icon: String?
    public var colorHex: String?
    public var lastOpenedAt: Date?
    public var validity: ProjectValidity?
    public var lastCheckedAt: Date?
    public var isStarred: Bool
    public var pinnedOrder: Int?

    public init(
        id: URL,
        name: String? = nil,
        icon: String? = nil,
        colorHex: String? = nil,
        lastOpenedAt: Date? = nil,
        validity: ProjectValidity? = nil,
        lastCheckedAt: Date? = nil,
        isStarred: Bool = false,
        pinnedOrder: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.lastOpenedAt = lastOpenedAt
        self.validity = validity
        self.lastCheckedAt = lastCheckedAt
        self.isStarred = isStarred
        self.pinnedOrder = pinnedOrder
    }
}

public enum ProjectValidity: String, Codable, Sendable {
    case valid
    case invalid
}

public enum ProjectRegistry {
    public static let defaultsKey = "ProjectRegistry"

    public static func load() -> [ProjectEntry] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ProjectEntry].self, from: data)) ?? []
    }

    public static func save(_ entries: [ProjectEntry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try? encoder.encode(entries)
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    public static func normalizeID(_ url: URL) -> URL {
        let expandedPath = (url.path(percentEncoded: false) as NSString).expandingTildeInPath
        let trimmedPath = ProjectRegistry.trimTrailingSlash(expandedPath)
        var normalized = URL(fileURLWithPath: trimmedPath).standardizedFileURL

        if FileManager.default.fileExists(atPath: normalized.path) {
            normalized = normalized.resolvingSymlinksInPath()
        }

        if let isCaseSensitive = ProjectRegistry.isCaseSensitiveVolume(for: normalized),
            !isCaseSensitive
        {
            normalized = URL(fileURLWithPath: normalized.path.lowercased())
        }

        return normalized
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
        do {
            let values = try url.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
            return values.volumeSupportsCaseSensitiveNames
        } catch {
            return nil
        }
    }

    public static func deduplicate(_ entries: [ProjectEntry]) -> [ProjectEntry] {
        var order: [URL] = []
        var merged: [URL: ProjectEntry] = [:]

        for entry in entries {
            let id = normalizeID(entry.id)
            if merged[id] == nil {
                order.append(id)
            }

            var combined = merged[id] ?? ProjectEntry(id: id)
            if (combined.name ?? "").isEmpty, let name = entry.name, !name.isEmpty {
                combined.name = name
            }
            if (combined.icon ?? "").isEmpty, let icon = entry.icon, !icon.isEmpty {
                combined.icon = icon
            }
            if (combined.colorHex ?? "").isEmpty, let colorHex = entry.colorHex, !colorHex.isEmpty {
                combined.colorHex = colorHex
            }
            if let date = entry.lastOpenedAt, (combined.lastOpenedAt ?? .distantPast) < date {
                combined.lastOpenedAt = date
            }
            if let checkedAt = entry.lastCheckedAt,
                (combined.lastCheckedAt ?? .distantPast) < checkedAt
            {
                combined.lastCheckedAt = checkedAt
            }
            if let validity = entry.validity {
                if combined.validity == nil {
                    combined.validity = validity
                } else if combined.validity == .invalid, validity == .valid {
                    combined.validity = .valid
                }
            }
            combined.isStarred = combined.isStarred || entry.isStarred
            if let orderValue = entry.pinnedOrder {
                if combined.pinnedOrder == nil || orderValue < (combined.pinnedOrder ?? orderValue) {
                    combined.pinnedOrder = orderValue
                }
            }

            merged[id] = combined
        }

        return order.compactMap { id in
            guard var entry = merged[id] else { return nil }
            if entry.name == "." {
                entry.name = nil
            }
            if !entry.isStarred {
                entry.pinnedOrder = nil
            }
            return entry
        }
    }
}

@MainActor
@Observable
public final class ProjectRegistryStore {
    public var entries: [ProjectEntry] {
        didSet {
            ProjectRegistry.save(entries)
        }
    }

    public init() {
        let loaded = ProjectRegistry.load()
        let deduped = ProjectRegistry.deduplicate(loaded)
        self.entries = deduped
        if deduped != loaded {
            ProjectRegistry.save(deduped)
        }
    }

    public func toggleStar(id: URL) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var entry = entries[index]
        entry.isStarred.toggle()
        if entry.isStarred, entry.pinnedOrder == nil {
            entry.pinnedOrder = nextPinnedOrder()
        }
        if !entry.isStarred {
            entry.pinnedOrder = nil
        }
        entries[index] = entry
    }

    public func updatePinnedOrder(ids: [URL]) {
        let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, $0.offset) })
        entries = entries.map { entry in
            guard entry.isStarred else { return entry }
            var updated = entry
            updated.pinnedOrder = order[entry.id]
            return updated
        }
    }

    public var starredEntries: [ProjectEntry] {
        entries
            .filter { $0.isStarred }
            .sorted { lhs, rhs in
                let lhsOrder = lhs.pinnedOrder ?? Int.max
                let rhsOrder = rhs.pinnedOrder ?? Int.max
                if lhsOrder != rhsOrder {
                    return lhsOrder < rhsOrder
                }
                return (lhs.lastOpenedAt ?? .distantPast) > (rhs.lastOpenedAt ?? .distantPast)
            }
    }

    public var recentEntries: [ProjectEntry] {
        entries
            .filter { !$0.isStarred }
            .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
    }

    private func nextPinnedOrder() -> Int {
        let maxOrder = entries.compactMap { $0.pinnedOrder }.max() ?? -1
        return maxOrder + 1
    }

    public func remove(id: URL) {
        entries.removeAll { $0.id == id }
    }

    public func refreshValidity() {
        let now = Date()
        entries = entries.map { entry in
            var updated = entry
            let isValid = ProjectRegistry.isAccessible(entry.id)
            updated.validity = isValid ? .valid : .invalid
            updated.lastCheckedAt = now
            return updated
        }
    }

    public func isInvalid(_ entry: ProjectEntry) -> Bool {
        entry.validity == .invalid
    }

    public func validateNow(_ entry: ProjectEntry) -> Bool {
        let isValid = ProjectRegistry.isAccessible(entry.id)
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            var updated = entries[index]
            updated.validity = isValid ? .valid : .invalid
            updated.lastCheckedAt = Date()
            entries[index] = updated
        }
        return isValid
    }
}

extension ProjectRegistry {
    public static func isAccessible(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return false
        }

        if isDirectory.boolValue {
            return FileManager.default.isReadableFile(atPath: path)
                && FileManager.default.isExecutableFile(atPath: path)
        }

        return FileManager.default.isReadableFile(atPath: path)
    }
}

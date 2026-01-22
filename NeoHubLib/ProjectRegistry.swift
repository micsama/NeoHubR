import Foundation

public struct ProjectEntry: Identifiable, Codable, Hashable, Sendable {
    public let id: URL
    public var name: String?
    public var icon: String?
    public var colorHex: String?
    public var lastOpenedAt: Date?
    public var isStarred: Bool
    public var pinnedOrder: Int?

    public init(
        id: URL,
        name: String? = nil,
        icon: String? = nil,
        colorHex: String? = nil,
        lastOpenedAt: Date? = nil,
        isStarred: Bool = false,
        pinnedOrder: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.lastOpenedAt = lastOpenedAt
        self.isStarred = isStarred
        self.pinnedOrder = pinnedOrder
    }
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
        let standardized = url.standardizedFileURL
        return URL(fileURLWithPath: standardized.path)
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
            if !entry.isStarred {
                entry.pinnedOrder = nil
            }
            return entry
        }
    }
}

@MainActor
public final class ProjectRegistryStore: ObservableObject {
    @Published public var entries: [ProjectEntry] {
        didSet {
            ProjectRegistry.save(entries)
        }
    }

    public init() {
        let loaded = ProjectRegistry.load()
        let deduped = ProjectRegistry.deduplicate(loaded)
        self.entries = deduped
        if deduped.count != loaded.count {
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

    private func nextPinnedOrder() -> Int {
        let maxOrder = entries.compactMap { $0.pinnedOrder }.max() ?? -1
        return maxOrder + 1
    }
}

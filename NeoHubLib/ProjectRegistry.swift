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
}

@MainActor
public final class ProjectRegistryStore: ObservableObject {
    @Published public var entries: [ProjectEntry] {
        didSet {
            ProjectRegistry.save(entries)
        }
    }

    public init() {
        self.entries = ProjectRegistry.load()
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

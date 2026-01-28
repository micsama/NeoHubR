import Foundation
import Observation

public struct ProjectEntry: Identifiable, Codable, Hashable, Sendable {
    public let id: URL
    public var name: String?
    public var icon: String?
    public var colorHex: String?
    public var sessionPath: URL?

    public init(
        id: URL,
        name: String? = nil,
        icon: String? = nil,
        colorHex: String? = nil,
        sessionPath: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.sessionPath = sessionPath
    }

    public var isSession: Bool {
        sessionPath != nil || id.pathExtension.lowercased() == "vim"
    }
}

public struct ProjectRegistryStorage: Codable, Sendable, Hashable {
    public var version: Int
    public var starred: [ProjectEntry]
    public var recent: [ProjectEntry]

    public init(version: Int = 1, starred: [ProjectEntry] = [], recent: [ProjectEntry] = []) {
        self.version = version
        self.starred = starred
        self.recent = recent
    }
}

public enum ProjectRegistry {
    public static let defaultsKey = "ProjectRegistry"

    public static func loadStorage() -> ProjectRegistryStorage {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            return ProjectRegistryStorage()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let storage = try? decoder.decode(ProjectRegistryStorage.self, from: data) {
            return storage
        }
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        return ProjectRegistryStorage()
    }

    public static func saveStorage(_ storage: ProjectRegistryStorage) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try? encoder.encode(storage)
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    public static func normalizeID(_ url: URL) -> URL {
        PathUtils.normalize(url)
    }

    public static func normalizeSessionPath(_ url: URL) -> URL {
        PathUtils.normalizeSessionPath(url)
    }

    public static func resolveSessionPath(workingDirectory: URL, path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        let rawURL: URL
        if path.hasPrefix("~") {
            let expanded = PathUtils.expandTilde(path)
            rawURL = URL(fileURLWithPath: expanded)
        } else if path.hasPrefix("/") {
            rawURL = URL(fileURLWithPath: path)
        } else {
            rawURL = workingDirectory.appendingPathComponent(path)
        }
        let standardized = rawURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory),
            !isDirectory.boolValue
        else {
            return nil
        }
        guard standardized.pathExtension.lowercased() == "vim" else {
            return nil
        }
        return normalizeSessionPath(standardized)
    }

    public static func isAccessible(_ url: URL) -> Bool {
        PathUtils.isAccessible(url)
    }

    public static func mergeEntry(base: ProjectEntry, incoming: ProjectEntry) -> ProjectEntry {
        var result = base
        if (result.name ?? "").isEmpty, let name = incoming.name, !name.isEmpty {
            result.name = name
        }
        if (result.icon ?? "").isEmpty, let icon = incoming.icon, !icon.isEmpty {
            result.icon = icon
        }
        if (result.colorHex ?? "").isEmpty, let colorHex = incoming.colorHex, !colorHex.isEmpty {
            result.colorHex = colorHex
        }
        if result.sessionPath == nil, let sessionPath = incoming.sessionPath {
            result.sessionPath = normalizeSessionPath(sessionPath)
        }
        return result
    }
}

@MainActor
@Observable
public final class ProjectRegistryStore {
    private var invalidIDs: Set<URL> = []
    private var storage: ProjectRegistryStorage {
        didSet {
            ProjectRegistry.saveStorage(storage)
        }
    }

    public init() {
        self.storage = ProjectRegistry.loadStorage()
    }

    public var starredEntries: [ProjectEntry] {
        storage.starred
    }

    public var recentEntries: [ProjectEntry] {
        storage.recent
    }

    public var entries: [ProjectEntry] {
        storage.starred + storage.recent
    }

    public func lookup(id: URL) -> (entry: ProjectEntry, isStarred: Bool)? {
        // Try exact match first (fast path & robust for invalid projects)
        if let entry = storage.starred.first(where: { $0.id == id }) {
            return (entry, true)
        }
        if let entry = storage.recent.first(where: { $0.id == id }) {
            return (entry, false)
        }
        
        // Fallback to normalized match for external inputs (CLI)
        let normalized = ProjectRegistry.normalizeID(id)
        if let entry = storage.starred.first(where: { $0.id == normalized }) {
            return (entry, true)
        }
        if let entry = storage.recent.first(where: { $0.id == normalized }) {
            return (entry, false)
        }
        return nil
    }

    public func remove(id: URL) {
        // Fix: Use exact match. Do NOT normalize, as it drifts for missing files.
        let starred = storage.starred.filter { $0.id != id }
        let recent = storage.recent.filter { $0.id != id }
        storage = ProjectRegistryStorage(starred: starred, recent: recent)
        invalidIDs.remove(id)
    }

    public func refreshValidity() {
        var invalid: Set<URL> = []
        for entry in storage.starred + storage.recent {
            // Fix: Check stored ID directly.
            if !ProjectRegistry.isAccessible(entry.id) {
                invalid.insert(entry.id)
            }
        }
        invalidIDs = invalid
    }

    public func isInvalid(_ entry: ProjectEntry) -> Bool {
        return invalidIDs.contains(entry.id)
    }

    public func moveStarred(fromOffsets: IndexSet, toOffset: Int) {
        var starred = storage.starred
        starred.move(fromOffsets: fromOffsets, toOffset: toOffset)
        storage = ProjectRegistryStorage(starred: starred, recent: storage.recent)
    }

    public func toggleStar(id: URL) {
        // Fix: Use exact match first
        var starred = storage.starred
        var recent = storage.recent

        if let index = starred.firstIndex(where: { $0.id == id }) {
            let entry = starred.remove(at: index)
            recent.insert(entry, at: 0)
            storage = ProjectRegistryStorage(starred: starred, recent: recent)
            return
        }

        if let index = recent.firstIndex(where: { $0.id == id }) {
            let entry = recent.remove(at: index)
            starred.append(entry)
            storage = ProjectRegistryStorage(starred: starred, recent: recent)
            return
        }
        
        // Fallback logic could be added here if needed, but UI passes exact ID.
    }

    public func touchRecent(root: URL, name: String? = nil, sessionPath: URL? = nil) {
        let normalizedRoot = ProjectRegistry.normalizeID(root)
        let normalizedSession = sessionPath.map { ProjectRegistry.normalizeSessionPath($0) }
        let entryName = name ?? normalizedRoot.lastPathComponent
        let incoming = ProjectEntry(
            id: normalizedRoot,
            name: entryName,
            sessionPath: normalizedSession
        )

        var starred = storage.starred
        var recent = storage.recent

        if let index = starred.firstIndex(where: { $0.id == normalizedRoot }) {
            let merged = ProjectRegistry.mergeEntry(base: starred[index], incoming: incoming)
            starred[index] = merged
            storage = ProjectRegistryStorage(starred: starred, recent: recent)
            return
        }

        if let index = recent.firstIndex(where: { $0.id == normalizedRoot }) {
            let merged = ProjectRegistry.mergeEntry(base: recent[index], incoming: incoming)
            recent.remove(at: index)
            recent.insert(merged, at: 0)
            storage = ProjectRegistryStorage(starred: starred, recent: recent)
            return
        }

        recent.insert(incoming, at: 0)
        storage = ProjectRegistryStorage(starred: starred, recent: recent)
    }

    public func entry(for id: URL) -> ProjectEntry? {
        lookup(id: id)?.entry
    }

    public func addProject(root: URL, name: String? = nil, sessionPath: URL? = nil) {
        let normalizedRoot = ProjectRegistry.normalizeID(root)
        let normalizedSession = sessionPath.map { ProjectRegistry.normalizeSessionPath($0) }
        let entryName = name ?? normalizedRoot.lastPathComponent
        let entry = ProjectEntry(
            id: normalizedRoot,
            name: entryName,
            icon: nil,
            colorHex: nil,
            sessionPath: normalizedSession
        )

        var starred = storage.starred
        var recent = storage.recent

        if let index = starred.firstIndex(where: { $0.id == normalizedRoot }) {
            let merged = ProjectRegistry.mergeEntry(base: starred[index], incoming: entry)
            starred[index] = merged
            storage = ProjectRegistryStorage(starred: starred, recent: recent)
            updateInvalidCache(for: normalizedRoot)
            return
        }

        if let index = recent.firstIndex(where: { $0.id == normalizedRoot }) {
            let merged = ProjectRegistry.mergeEntry(base: recent[index], incoming: entry)
            recent.remove(at: index)
            starred.append(merged)
            storage = ProjectRegistryStorage(starred: starred, recent: recent)
            updateInvalidCache(for: normalizedRoot)
            return
        }

        starred.append(entry)
        storage = ProjectRegistryStorage(starred: starred, recent: recent)
        updateInvalidCache(for: normalizedRoot)
    }

    public func updateEntry(_ entry: ProjectEntry, replacing oldID: URL? = nil) {
        let normalizedEntry = ProjectEntry(
            id: ProjectRegistry.normalizeID(entry.id),
            name: entry.name,
            icon: entry.icon,
            colorHex: entry.colorHex,
            sessionPath: entry.sessionPath.map { ProjectRegistry.normalizeSessionPath($0) }
        )

        var starred = storage.starred
        var recent = storage.recent

        // Fix: Determine targetID safely.
        // If oldID is provided and exists in storage, use it exactly.
        // Otherwise, normalize it or fallback to new ID.
        var targetID = normalizedEntry.id
        if let old = oldID {
            if starred.contains(where: { $0.id == old }) || recent.contains(where: { $0.id == old }) {
                targetID = old
            } else {
                targetID = ProjectRegistry.normalizeID(old)
            }
        }

        if targetID != normalizedEntry.id {
            starred.removeAll { $0.id == normalizedEntry.id }
            recent.removeAll { $0.id == normalizedEntry.id }
            invalidIDs.remove(targetID)
        }

        if let index = starred.firstIndex(where: { $0.id == targetID }) {
            starred[index] = normalizedEntry
            storage = ProjectRegistryStorage(starred: starred, recent: recent)
            updateInvalidCache(for: normalizedEntry.id)
            return
        }

        if let index = recent.firstIndex(where: { $0.id == targetID }) {
            recent[index] = normalizedEntry
            storage = ProjectRegistryStorage(starred: starred, recent: recent)
            updateInvalidCache(for: normalizedEntry.id)
            return
        }

        recent.insert(normalizedEntry, at: 0)
        storage = ProjectRegistryStorage(starred: starred, recent: recent)
        updateInvalidCache(for: normalizedEntry.id)
    }

    private func updateInvalidCache(for id: URL) {
        // Use exact ID as provided (it's already normalized by add/update logic)
        if ProjectRegistry.isAccessible(id) {
            invalidIDs.remove(id)
        } else {
            invalidIDs.insert(id)
        }
    }
}

extension Array {
    fileprivate mutating func move(fromOffsets offsets: IndexSet, toOffset: Int) {
        let elements = offsets.map { self[$0] }
        let adjustedOffset = toOffset - offsets.filter { $0 < toOffset }.count
        for index in offsets.sorted(by: >) {
            remove(at: index)
        }
        insert(contentsOf: elements, at: adjustedOffset)
    }
}

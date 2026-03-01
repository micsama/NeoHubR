import Foundation
import NeoHubRLib

struct ActiveEditorSnapshot: Codable {
    let id: URL
    let name: String
    let pid: Int32?
    let lastAccessTime: TimeInterval
    let request: RunRequest

    init(
        id: URL,
        name: String,
        pid: Int32?,
        lastAccessTime: TimeInterval,
        request: RunRequest
    ) {
        self.id = id
        self.name = name
        self.pid = pid
        self.lastAccessTime = lastAccessTime
        self.request = request
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case pid
        case lastAccessTime
        case request
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(URL.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.pid = try container.decodeIfPresent(Int32.self, forKey: .pid)
        self.lastAccessTime = try container.decode(TimeInterval.self, forKey: .lastAccessTime)
        self.request = try container.decode(RunRequest.self, forKey: .request)
    }
}

final class ActiveEditorStore {
    private let fileManager: FileManager
    private let fileURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = fileManager.temporaryDirectory.appendingPathComponent("neohubr.instances.json")
    }

    func loadSnapshots() -> [ActiveEditorSnapshot] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode([ActiveEditorSnapshot].self, from: data)
        } catch {
            log.error("Failed to decode active editor snapshots: \(error)")
            return []
        }
    }

    func saveSnapshots(_ snapshots: [ActiveEditorSnapshot]) {
        guard !snapshots.isEmpty else {
            try? fileManager.removeItem(at: fileURL)
            return
        }

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(snapshots)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            log.error("Failed to save active editor snapshots: \(error)")
        }
    }
}

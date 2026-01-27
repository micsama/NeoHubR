import Foundation
import NeoHubRLib

struct ActiveEditorSnapshot: Codable {
    let id: URL
    let name: String
    let pid: Int32
    let lastAccessTime: TimeInterval
    let request: RunRequest
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
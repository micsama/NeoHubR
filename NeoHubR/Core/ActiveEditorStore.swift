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

    init(
        fileManager: FileManager = .default,
        fileURL: URL = URL(fileURLWithPath: "/tmp/neohubr.instances.json")
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL
    }

    func loadSnapshots() -> [ActiveEditorSnapshot] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        return (try? decoder.decode([ActiveEditorSnapshot].self, from: data)) ?? []
    }

    func saveSnapshots(_ snapshots: [ActiveEditorSnapshot]) {
        guard !snapshots.isEmpty else {
            try? fileManager.removeItem(at: fileURL)
            return
        }

        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(snapshots) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

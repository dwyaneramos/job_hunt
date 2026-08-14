import Foundation

enum DismissedStore {
    static let fileURL: URL = JobDataLoader.sharedDir.appendingPathComponent("dismissed.json")

    static func load() -> Set<String> {
        guard let data = try? Data(contentsOf: fileURL),
              let ids = try? JSONDecoder().decode(Set<String>.self, from: data) else {
            return []
        }
        return ids
    }

    static func save(_ ids: Set<String>) {
        guard let data = try? JSONEncoder().encode(ids) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func dismiss(_ id: String) {
        var ids = load()
        ids.insert(id)
        save(ids)
    }
}

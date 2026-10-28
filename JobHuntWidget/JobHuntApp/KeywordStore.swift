import Foundation

/// Keyword lists the scraper filters by. Saved to keywords.json next to
/// jobs.json; the scraper reads it on every run. Until the file exists the
/// lists are seeded from the scraper's config.json.
@MainActor
final class KeywordStore: ObservableObject {
    @Published private(set) var want: [String] = []
    @Published private(set) var skip: [String] = []

    private let scraperDir = "/Users/dwyaneramos/Code/job_hunt/scraper"
    private var fileURL: URL { JobDataLoader.sharedDir.appendingPathComponent("keywords.json") }

    private struct Lists: Codable {
        var want: [String]
        var skip: [String]
    }

    init() {
        load()
    }

    func addWant(_ text: String) {
        guard let word = Self.clean(text), !want.contains(word) else { return }
        want.append(word)
        save()
    }

    func addSkip(_ text: String) {
        guard let word = Self.clean(text), !skip.contains(word) else { return }
        skip.append(word)
        save()
    }

    func removeWant(_ word: String) {
        want.removeAll { $0 == word }
        save()
    }

    func removeSkip(_ word: String) {
        skip.removeAll { $0 == word }
        save()
    }

    private static func clean(_ text: String) -> String? {
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return word.isEmpty ? nil : word
    }

    private func load() {
        if let data = try? Data(contentsOf: fileURL),
           let lists = try? JSONDecoder().decode(Lists.self, from: data) {
            want = lists.want
            skip = lists.skip
            return
        }
        let configURL = URL(fileURLWithPath: "\(scraperDir)/config.json")
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        want = config["default_want_keywords"] as? [String] ?? []
        skip = config["exclude_keywords"] as? [String] ?? []
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: JobDataLoader.sharedDir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Lists(want: want, skip: skip))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Could not save keywords: \(error)")
        }
    }
}

import Foundation
import os.log

private let logger = Logger(subsystem: "com.dwyaneramos.jobhuntwidget.app", category: "JobDataLoader")

enum JobDataLoader {
    // Hardcoded real path — under App Sandbox, homeDirectoryForCurrentUser
    // resolves to the process's virtualized container home, not the real
    // one that the temporary-exception entitlement (and the external Python
    // scraper) actually operate on.
    static let sharedDir = URL(fileURLWithPath: "/Users/dwyaneramos/Library/Application Support/JobHuntWidget")

    static let fileURL: URL = sharedDir.appendingPathComponent("jobs.json")

    static func load() -> JobFeed? {
        logger.notice("Loading jobs from \(fileURL.path, privacy: .public)")
        guard let data = try? Data(contentsOf: fileURL) else {
            logger.error("Could not read data at \(fileURL.path, privacy: .public)")
            return nil
        }
        logger.notice("Read \(data.count, privacy: .public) bytes")
        do {
            let feed = try JSONDecoder().decode(JobFeed.self, from: data)
            logger.notice("Decoded \(feed.jobs.count, privacy: .public) jobs")
            return feed
        } catch {
            logger.error("Decode failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}

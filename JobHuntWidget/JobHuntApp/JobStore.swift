import Foundation
import WidgetKit

@MainActor
final class JobStore: ObservableObject {
    @Published var feed: JobFeed?
    @Published var isRefreshing = false
    @Published var lastError: String?
    @Published var dismissedIDs: Set<String> = DismissedStore.load()

    private let scraperDir = "/Users/dwyaneramos/Code/job_hunt/scraper"

    var visibleJobs: [Job] {
        (feed?.jobs ?? []).filter { !dismissedIDs.contains($0.id) }
    }

    var dismissedCount: Int { dismissedIDs.count }

    func load() {
        feed = JobDataLoader.load()
    }

    func dismiss(_ job: Job) {
        dismissedIDs.insert(job.id)
        DismissedStore.save(dismissedIDs)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func restoreAllDismissed() {
        dismissedIDs.removeAll()
        DismissedStore.save(dismissedIDs)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func refreshNow() {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastError = nil

        let pythonPath = "\(scraperDir)/venv/bin/python"
        let scriptPath = "\(scraperDir)/scraper.py"

        Task.detached(priority: .userInitiated) { [scraperDir] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: pythonPath)
            process.arguments = [scriptPath]
            process.currentDirectoryURL = URL(fileURLWithPath: scraperDir)

            let pipe = Pipe()
            process.standardError = pipe

            var errorOutput: String?
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    errorOutput = String(data: data, encoding: .utf8)
                }
            } catch {
                errorOutput = error.localizedDescription
            }

            await MainActor.run {
                self.load()
                self.isRefreshing = false
                self.lastError = errorOutput
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}

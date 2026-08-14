import WidgetKit
import SwiftUI

struct JobEntry: TimelineEntry {
    let date: Date
    let jobs: [Job]
    let hasData: Bool
    let newJobCount: Int
}

struct Provider: TimelineProvider {
    private func makeEntry() -> JobEntry {
        let feed = JobDataLoader.load()
        let dismissed = DismissedStore.load()
        let jobs = (feed?.jobs ?? []).filter { !dismissed.contains($0.id) }
        return JobEntry(date: Date(), jobs: jobs, hasData: feed != nil, newJobCount: feed?.newJobCount ?? 0)
    }

    func placeholder(in context: Context) -> JobEntry {
        JobEntry(date: Date(), jobs: [], hasData: false, newJobCount: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (JobEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<JobEntry>) -> Void) {
        let entry = makeEntry()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct JobRowView: View {
    let job: Job

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Link(destination: URL(string: job.url) ?? URL(string: "https://www.linkedin.com/jobs/")!) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(job.title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text("\(job.company) · \(job.source)")
                        if let posted = job.postedRelative {
                            Text("· \(posted)")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(intent: DismissJobIntent(jobID: job.id)) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}

struct JobHuntWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    private var maxRows: Int {
        switch family {
        case .systemSmall: return 2
        case .systemMedium: return 3
        case .systemLarge: return 7
        default: return 3
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "briefcase.fill")
                    .foregroundStyle(.tint)
                Text("Job Hunt")
                    .font(.headline)
                Spacer()
                if entry.newJobCount > 0 {
                    Text("+\(entry.newJobCount) new")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                }
                Text("\(entry.jobs.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if entry.jobs.isEmpty {
                Spacer()
                Text(entry.hasData ? "No jobs right now." : "Run the scraper to load jobs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(entry.jobs.prefix(maxRows)) { job in
                    JobRowView(job: job)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct JobHuntWidget: Widget {
    let kind: String = "JobHuntWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            JobHuntWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Job Hunt")
        .description("Latest software developer, engineering, internship and graduate roles.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview(as: .systemMedium) {
    JobHuntWidget()
} timeline: {
    JobEntry(date: .now, jobs: [], hasData: false, newJobCount: 0)
}

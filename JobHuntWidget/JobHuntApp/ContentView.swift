import SwiftUI
import WidgetKit

struct ContentView: View {
    @StateObject private var store = JobStore()
    @State private var searchText = ""

    private var filteredJobs: [Job] {
        let jobs = store.visibleJobs
        if searchText.isEmpty { return jobs }
        return jobs.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.company.localizedCaseInsensitiveContains(searchText)
                || $0.location.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationSplitView {
            List {
                Section("Quick search") {
                    Text("Blocked from scraping — search manually")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ForEach(store.feed?.quickLinks ?? []) { link in
                        Link(destination: URL(string: link.url) ?? URL(string: "https://google.com")!) {
                            Label(link.source, systemImage: "arrow.up.right.square")
                        }
                        .help(link.reason)
                    }
                }

                if store.dismissedCount > 0 {
                    Section("Dismissed") {
                        Text("\(store.dismissedCount) hidden")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Restore All") {
                            store.restoreAllDismissed()
                        }
                    }
                }

                if let errors = store.feed?.errors, !errors.isEmpty {
                    Section("Source errors") {
                        ForEach(errors, id: \.source) { err in
                            Text("\(err.source): \(err.error)")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .frame(minWidth: 220)
        } detail: {
            VStack(spacing: 0) {
                HStack {
                    TextField("Search jobs, companies, locations", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        store.refreshNow()
                    } label: {
                        if store.isRefreshing {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Refresh Now", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(store.isRefreshing)
                }
                .padding()

                if let feed = store.feed {
                    HStack {
                        Text("\(filteredJobs.count) of \(store.visibleJobs.count) jobs")
                        if let date = feed.updatedAtDate {
                            Text("· updated \(date.formatted(.relative(presentation: .named)))")
                        }
                        if feed.newJobCount > 0 {
                            Text("· \(feed.newJobCount) new job\(feed.newJobCount == 1 ? "" : "s") found since last scrape")
                                .foregroundStyle(.green)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                } else {
                    Text("No data yet — click Refresh Now to scrape jobs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                }

                if let error = store.lastError {
                    Text("Scraper error: \(error)")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                List(filteredJobs) { job in
                    JobRow(job: job) {
                        store.dismiss(job)
                    }
                }
                .listStyle(.inset)
            }
        }
        .onAppear {
            store.load()
            WidgetCenter.shared.reloadAllTimelines()
        }
        .navigationTitle("Job Hunt")
        .frame(minWidth: 780, minHeight: 520)
    }
}

struct JobRow: View {
    let job: Job
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(job.title)
                        .font(.headline)
                    if job.isNew {
                        Text("NEW")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.green, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                Text("\(job.company) · \(job.location)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(job.source)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                    if let posted = job.postedRelative {
                        Text(posted)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Button("Apply") {
                if let url = URL(string: job.url) {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Hide this job — already applied, or not interested")
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
}

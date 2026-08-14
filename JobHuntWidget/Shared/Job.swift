import Foundation

struct Job: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let company: String
    let location: String
    let url: String
    let source: String
    let posted: String?
    let tags: [String]
    let isNew: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, company, location, url, source, posted, tags
        case isNew = "is_new"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        company = try c.decode(String.self, forKey: .company)
        location = try c.decode(String.self, forKey: .location)
        url = try c.decode(String.self, forKey: .url)
        source = try c.decode(String.self, forKey: .source)
        posted = try c.decodeIfPresent(String.self, forKey: .posted)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        isNew = try c.decodeIfPresent(Bool.self, forKey: .isNew) ?? false
    }

    private static let iso8601Fraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601Plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let rfc822: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss ZZZ"
        return f
    }()

    private static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var postedDate: Date? {
        guard let posted, !posted.isEmpty else { return nil }
        return Job.iso8601Fraction.date(from: posted)
            ?? Job.iso8601Plain.date(from: posted)
            ?? Job.rfc822.date(from: posted)
            ?? Job.dateOnly.date(from: posted)
    }

    var postedRelative: String? {
        guard let date = postedDate else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct QuickLink: Codable, Identifiable, Hashable {
    var id: String { source }
    let source: String
    let reason: String
    let url: String
}

struct ScrapeError: Codable, Hashable {
    let source: String
    let error: String
}

struct JobFeed: Codable {
    let updatedAt: String
    let jobCount: Int
    let newJobCount: Int
    let jobs: [Job]
    let quickLinks: [QuickLink]
    let errors: [ScrapeError]

    enum CodingKeys: String, CodingKey {
        case updatedAt = "updated_at"
        case jobCount = "job_count"
        case newJobCount = "new_job_count"
        case jobs
        case quickLinks = "quick_links"
        case errors
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
        jobCount = try c.decode(Int.self, forKey: .jobCount)
        newJobCount = try c.decodeIfPresent(Int.self, forKey: .newJobCount) ?? 0
        jobs = try c.decode([Job].self, forKey: .jobs)
        quickLinks = try c.decode([QuickLink].self, forKey: .quickLinks)
        errors = try c.decode([ScrapeError].self, forKey: .errors)
    }

    var updatedAtDate: Date? {
        ISO8601DateFormatter().date(from: updatedAt)
    }
}

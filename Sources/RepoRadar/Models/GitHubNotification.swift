import Foundation

/// Subset of the GitHub "thread" object returned by GET /notifications
struct GitHubNotification: Identifiable, Codable, Hashable {
    let id: String
    let unread: Bool
    let reason: String
    let updatedAt: Date
    let subject: Subject
    let repository: RepoRef

    struct Subject: Codable, Hashable {
        let title: String
        let type: String       // "PullRequest" | "Issue" | "Release" | ...
        let url: URL?
    }

    struct RepoRef: Codable, Hashable {
        let fullName: String

        enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
        }
    }

    /// Best-effort conversion of the API subject URL into a browsable web URL.
    var webURL: URL {
        if let api = subject.url {
            var s = api.absoluteString
            s = s.replacingOccurrences(of: "api.github.com/repos", with: "github.com")
            s = s.replacingOccurrences(of: "/pulls/", with: "/pull/")
            if let url = URL(string: s) { return url }
        }
        return URL(string: "https://github.com/\(repository.fullName)")!
    }

    enum CodingKeys: String, CodingKey {
        case id, unread, reason, subject, repository
        case updatedAt = "updated_at"
    }
}

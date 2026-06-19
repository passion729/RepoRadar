import Foundation

enum GitHubError: LocalizedError {
    case notAuthenticated
    case http(Int, String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return Localizer.t(.ghNotAuthenticated)
        case .http(let code, let message):
            return Localizer.t(.ghHTTP(code, message))
        case .decoding(let message):
            return Localizer.t(.ghDecoding(message))
        }
    }
}

/// Thin async wrapper around the GitHub REST API.
actor GitHubClient {
    static let shared = GitHubClient()

    private let base = URL(string: "https://api.github.com")!

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Per-endpoint ETag cache for conditional requests (304 ⇒ unchanged,
    /// and 304 responses don't count against the rate limit).
    private var etags: [String: String] = [:]
    /// Server-suggested poll interval (seconds) per endpoint, from `X-Poll-Interval`.
    private var pollIntervals: [String: Int] = [:]

    private static let notificationsKey = "/notifications"

    // MARK: - Requests

    private func makeRequest(path: String, query: [URLQueryItem] = []) throws -> URLRequest {
        guard let token = KeychainStore.loadToken(), !token.isEmpty else {
            throw GitHubError.notAuthenticated
        }

        var components = URLComponents(
            url: base.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty { components.queryItems = query }

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("RepoRadar", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubError.http(-1, Localizer.t(.noHTTPResponse))
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GitHubError.http(http.statusCode, body)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw GitHubError.decoding(String(describing: error))
        }
    }

    /// Conditional GET: sends `If-None-Match` from the cache and returns `nil`
    /// on `304 Not Modified` (caller keeps its existing data). Also records any
    /// `X-Poll-Interval` the server suggests.
    private func conditionalSend<T: Decodable>(
        _ request: URLRequest,
        cacheKey: String,
        as type: T.Type
    ) async throws -> T? {
        var request = request
        if let etag = etags[cacheKey] {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubError.http(-1, Localizer.t(.noHTTPResponse))
        }
        if let poll = http.value(forHTTPHeaderField: "X-Poll-Interval"), let seconds = Int(poll) {
            pollIntervals[cacheKey] = seconds
        }
        if http.statusCode == 304 { return nil }
        guard (200..<300).contains(http.statusCode) else {
            throw GitHubError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        if let etag = http.value(forHTTPHeaderField: "ETag") {
            etags[cacheKey] = etag
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw GitHubError.decoding(String(describing: error))
        }
    }

    /// Seconds to wait before polling notifications again (server-driven, ≥ 60).
    func notificationsPollSeconds() -> Int {
        max(60, pollIntervals[Self.notificationsKey] ?? 60)
    }

    // MARK: - Endpoints

    /// Open PRs for a repo. Returns `nil` when unchanged since the last fetch
    /// (HTTP 304), so the caller keeps the data it already has.
    func pullRequests(for repo: Repository, state: String = "open") async throws -> [PullRequest]? {
        let key = "pulls:\(repo.owner)/\(repo.name):\(state)"
        let request = try makeRequest(
            path: "/repos/\(repo.owner)/\(repo.name)/pulls",
            query: [
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "per_page", value: "50")
            ]
        )
        return try await conditionalSend(request, cacheKey: key, as: [PullRequest].self)
    }

    /// Every PR related to the authenticated user across all repos (any state) —
    /// authored, assigned, review-requested, or mentioned. Runs one search per
    /// relationship in parallel, then merges by PR id (a PR can match several).
    func relatedOpenPullRequests() async throws -> [RelatedPullRequest] {
        var merged: [Int: RelatedPullRequest] = [:]
        try await withThrowingTaskGroup(of: (PRRelation, [PullRequest]).self) { group in
            for relation in PRRelation.allCases {
                group.addTask {
                    (relation, try await self.searchPRs(qualifier: relation.searchQualifier))
                }
            }
            for try await (relation, prs) in group {
                for pr in prs {
                    merged[pr.id, default: RelatedPullRequest(pr: pr, relations: [])]
                        .relations.insert(relation)
                }
            }
        }
        return Array(merged.values)
    }

    private func searchPRs(qualifier: String) async throws -> [PullRequest] {
        let request = try makeRequest(
            path: "/search/issues",
            query: [
                URLQueryItem(name: "q", value: "is:pr \(qualifier)"),
                URLQueryItem(name: "sort", value: "updated"),
                URLQueryItem(name: "per_page", value: "100")
            ]
        )
        return try await send(request, as: SearchResult<PullRequest>.self).items
    }

    /// Notifications via a conditional request. Returns `nil` when unchanged
    /// (HTTP 304); 304s are free (don't count against the rate limit).
    func notifications(all: Bool = false) async throws -> [GitHubNotification]? {
        let request = try makeRequest(
            path: "/notifications",
            query: [URLQueryItem(name: "all", value: all ? "true" : "false")]
        )
        return try await conditionalSend(request, cacheKey: Self.notificationsKey, as: [GitHubNotification].self)
    }

    /// Confirms a repo exists and is reachable with the current token.
    func verify(repo: Repository) async throws {
        let request = try makeRequest(path: "/repos/\(repo.owner)/\(repo.name)")
        _ = try await send(request, as: RepoCheck.self)
    }

    private struct RepoCheck: Decodable {
        let full_name: String
    }

    /// Wrapper for the GitHub search API, which nests results under `items`.
    private struct SearchResult<T: Decodable>: Decodable {
        let items: [T]
    }
}

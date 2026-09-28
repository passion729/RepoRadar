import Foundation
import Security

struct RateLimit: Hashable {
    let remaining: Int
    let limit: Int
}

struct GitHubError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Keychain storage for the GitHub token.
enum Keychain {
    private static let base: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.reporadar.app",
        kSecAttrAccount as String: "github-token"
    ]

    static func save(_ token: String) {
        SecItemDelete(base as CFDictionary)
        var attributes = base
        attributes[kSecValueData as String] = Data(token.utf8)
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func load() -> String? {
        #if DEBUG
        // Rebuilt debug binaries lose Keychain trust and re-prompt each launch,
        // so debug builds read `REPORADAR_TOKEN` or ~/.reporadar-dev-token first.
        let env = ProcessInfo.processInfo.environment["REPORADAR_TOKEN"]
        let file = try? String(contentsOfFile: NSHomeDirectory() + "/.reporadar-dev-token", encoding: .utf8)
        if let dev = (env ?? file)?.trimmingCharacters(in: .whitespacesAndNewlines), !dev.isEmpty { return dev }
        #endif
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        SecItemDelete(base as CFDictionary)
    }
}

/// Async GitHub REST client. GETs use ETags: a 304 doesn't count against the rate limit.
actor GitHubClient {
    static let shared = GitHubClient()

    private var cache: [URL: (etag: String, data: Data)] = [:]
    /// Core REST quota from the latest response headers (search has its own, smaller quota).
    private(set) var rateLimit: RateLimit?
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func resetCache() { cache = [:] }

    @discardableResult
    private func send(_ path: String, query: [String: String] = [:], method: String = "GET") async throws -> Data {
        guard let token = Keychain.load(), !token.isEmpty else {
            throw GitHubError(message: "Not signed in to GitHub. Sign in from Settings (⌘,).")
        }
        var components = URLComponents(string: "https://api.github.com" + path)!
        if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        let url = components.url!

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if method == "GET", let etag = cache[url]?.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.value(forHTTPHeaderField: "X-RateLimit-Resource") == "core",
           let remaining = Int(http.value(forHTTPHeaderField: "X-RateLimit-Remaining") ?? ""),
           let limit = Int(http.value(forHTTPHeaderField: "X-RateLimit-Limit") ?? "") {
            rateLimit = RateLimit(remaining: remaining, limit: limit)
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        if code == 304, let cached = cache[url] { return cached.data }
        guard (200..<300).contains(code) else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["message"]
            throw GitHubError(message: "GitHub HTTP \(code): \(message ?? String(decoding: data, as: UTF8.self))")
        }
        if method == "GET", let etag = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "ETag") {
            cache[url] = (etag, data)
        }
        return data
    }

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        let data = try await send(path, query: query)
        do { return try decoder.decode(T.self, from: data) } catch {
            throw GitHubError(message: "Failed to decode \(path): \(error)")
        }
    }

    // MARK: - Endpoints

    func login() async throws -> String {
        struct User: Decodable { let login: String }
        let user: User = try await get("/user")
        return user.login
    }

    /// Non-archived repos you own / collaborate on / belong to via an org, pushed since `cutoff`.
    func repos(pushedSince cutoff: Date) async throws -> [Repo] {
        var all: [Repo] = []
        for page in 1... {
            let batch: [Repo] = try await get("/user/repos", query: [
                "affiliation": "owner,collaborator,organization_member",
                "sort": "pushed", "per_page": "100", "page": "\(page)"
            ])
            all += batch
            // Sorted by push date, so stop as soon as we pass the cutoff.
            if batch.count < 100 || (batch.last?.pushedAt ?? .distantPast) < cutoff { break }
        }
        return all.filter { !$0.archived && ($0.pushedAt ?? .distantPast) >= cutoff }
    }

    func runs(of repo: String) async throws -> [WorkflowRun] {
        let page: WorkflowRunsPage = try await get("/repos/\(repo)/actions/runs", query: ["per_page": "30"])
        return page.workflowRuns
    }

    func runs(of repo: String, headSHA: String) async throws -> [WorkflowRun] {
        let page: WorkflowRunsPage = try await get("/repos/\(repo)/actions/runs", query: ["head_sha": headSHA, "per_page": "30"])
        return page.workflowRuns
    }

    /// The workflow YAML exactly as it was at the run's commit.
    func workflowFile(of run: WorkflowRun) async throws -> String {
        struct Contents: Decodable { let content: String }
        guard let path = run.path?.split(separator: "@").first, let sha = run.headSha else {
            throw GitHubError(message: "This run has no workflow file.")
        }
        let file: Contents = try await get("/repos/\(run.repo)/contents/\(path)", query: ["ref": sha])
        guard let data = Data(base64Encoded: file.content, options: .ignoreUnknownCharacters) else {
            throw GitHubError(message: "Couldn't decode \(path).")
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// The run a CI notification is about: same workflow and branch, updated closest to the notification.
    func run(for notification: GitHubNotification) async throws -> WorkflowRun? {
        guard let hint = notification.workflowRunHint else { return nil }
        let page: WorkflowRunsPage = try await get("/repos/\(notification.repo)/actions/runs",
                                                   query: ["branch": hint.branch, "per_page": "50"])
        return page.workflowRuns
            .filter { $0.workflowName == hint.workflow }
            .min { abs($0.updatedAt.timeIntervalSince(notification.updatedAt)) < abs($1.updatedAt.timeIntervalSince(notification.updatedAt)) }
    }

    func jobs(of run: WorkflowRun) async throws -> [WorkflowJob] {
        let page: JobsPage = try await get("/repos/\(run.repo)/actions/runs/\(run.id)/jobs", query: ["per_page": "50"])
        return page.jobs
    }

    func rerunFailedJobs(_ run: WorkflowRun) async throws {
        try await send("/repos/\(run.repo)/actions/runs/\(run.id)/rerun-failed-jobs", method: "POST")
    }

    func rerun(_ run: WorkflowRun) async throws {
        try await send("/repos/\(run.repo)/actions/runs/\(run.id)/rerun", method: "POST")
    }

    func cancel(_ run: WorkflowRun) async throws {
        try await send("/repos/\(run.repo)/actions/runs/\(run.id)/cancel", method: "POST")
    }

    // MARK: Notifications

    /// Read and unread threads, newest first. Threads marked done drop out of this list on GitHub's side.
    func notifications() async throws -> [GitHubNotification] {
        // ponytail: first 50 threads only; page through `Link` headers if the inbox needs to go deeper
        try await get("/notifications", query: ["all": "true", "per_page": "50"])
    }

    func markRead(_ notification: GitHubNotification) async throws {
        try await send("/notifications/threads/\(notification.id)", method: "PATCH")
    }

    func markDone(_ notification: GitHubNotification) async throws {
        try await send("/notifications/threads/\(notification.id)", method: "DELETE")
    }

    // MARK: Issues & pull requests

    /// Open, non-archived pull requests matching a search qualifier such as `author:@me`.
    func searchPullRequests(_ qualifier: String) async throws -> [PullRequest] {
        let page: SearchPage<PullRequest> = try await get("/search/issues", query: [
            "q": "is:pr is:open archived:false \(qualifier)",
            "sort": "updated", "order": "desc", "per_page": "50"
        ])
        return page.items
    }

    func issue(_ ref: IssueRef) async throws -> IssueDetail {
        try await get("/repos/\(ref.repo)/issues/\(ref.number)")
    }

    func pull(_ ref: IssueRef) async throws -> PullDetail {
        try await get("/repos/\(ref.repo)/pulls/\(ref.number)")
    }

    func comments(_ ref: IssueRef) async throws -> [IssueComment] {
        try await get("/repos/\(ref.repo)/issues/\(ref.number)/comments", query: ["per_page": "50"])
    }
}

// MARK: - OAuth device flow

struct DeviceCode: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationUri: URL
    let expiresIn: Int
    let interval: Int
}

/// GitHub OAuth Device Flow: no client secret, no redirect URL.
/// The OAuth App must have "Enable Device Flow" turned on.
enum DeviceFlow {
    // Public client_id carried over from the original RepoRadar; swap in your own OAuth App's id if you like.
    static let clientID = "Ov23liBIfzKlrQskIuWA"
    static let scopes = "repo notifications"

    private struct PollResponse: Decodable {
        let accessToken: String?
        let error: String?
        let errorDescription: String?
        let interval: Int?
    }

    static func requestCode() async throws -> DeviceCode {
        try await post("https://github.com/login/device/code", ["client_id": clientID, "scope": scopes])
    }

    static func poll(_ code: DeviceCode) async throws -> String {
        var interval = max(code.interval, 1)
        let deadline = Date().addingTimeInterval(TimeInterval(code.expiresIn))
        while Date() < deadline {
            try await Task.sleep(for: .seconds(interval))
            let result: PollResponse = try await post("https://github.com/login/oauth/access_token", [
                "client_id": clientID,
                "device_code": code.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
            ])
            if let token = result.accessToken, !token.isEmpty { return token }
            switch result.error {
            case "authorization_pending": continue
            case "slow_down": interval = result.interval ?? interval + 5
            case "access_denied": throw GitHubError(message: "Authorization was denied.")
            default: throw GitHubError(message: result.errorDescription ?? result.error ?? "Unexpected response.")
            }
        }
        throw GitHubError(message: "The device code expired. Please try again.")
    }

    private static func post<T: Decodable>(_ url: String, _ fields: [String: String]) async throws -> T {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var body = URLComponents()
        body.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }
}

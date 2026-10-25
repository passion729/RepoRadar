import Foundation
import Security

struct RateLimit: Hashable {
    let remaining: Int
    let limit: Int
    /// When the quota refills.
    var reset: Date?
}

struct GitHubError: LocalizedError {
    /// GitHub's own reason, e.g. "At least 2 approving reviews are required by reviewers with write access."
    let message: String
    /// HTTP status, when the error came from a response.
    var status: Int?
    var errorDescription: String? { status.map { "GitHub HTTP \($0): \(message)" } ?? message }

    /// The reason from an error response: `message` plus any `errors` details (objects or plain strings).
    static func reason(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let details = (json["errors"] as? [Any] ?? []).compactMap { item -> String? in
            if let text = item as? String { return text }
            guard let object = item as? [String: Any] else { return nil }
            return object["message"] as? String ?? (object["code"] as? String).map { "\($0) \(object["field"] as? String ?? "")" }
        }
        let message = json["message"] as? String
        return ([message].compactMap { $0 } + details).joined(separator: ": ").nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
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
    /// Seconds GitHub asks to wait between notification polls (`X-Poll-Interval`).
    private(set) var pollInterval: Int?
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func resetCache() { cache = [:] }

    @discardableResult
    private func send(_ path: String, query: [String: String] = [:], method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        guard let token = Keychain.load(), !token.isEmpty else {
            throw GitHubError(message: "Not signed in to GitHub. Sign in from Settings (⌘,).", status: 401)
        }
        var components = URLComponents(string: Config.apiHost + path)!
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
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if path == "/notifications", let interval = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-Poll-Interval") {
            pollInterval = Int(interval)
        }
        if let http = response as? HTTPURLResponse, http.value(forHTTPHeaderField: "X-RateLimit-Resource") == "core",
           let remaining = Int(http.value(forHTTPHeaderField: "X-RateLimit-Remaining") ?? ""),
           let limit = Int(http.value(forHTTPHeaderField: "X-RateLimit-Limit") ?? "") {
            let reset = Double(http.value(forHTTPHeaderField: "X-RateLimit-Reset") ?? "").map(Date.init(timeIntervalSince1970:))
            rateLimit = RateLimit(remaining: remaining, limit: limit, reset: reset)
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        if code == 304, let cached = cache[url] { return cached.data }
        guard (200..<300).contains(code) else {
            let http = response as? HTTPURLResponse
            // As RepoBar does: a 403/429 with no quota left or a Retry-After is rate limiting, whatever the body says.
            if [403, 429].contains(code),
               http?.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" || http?.value(forHTTPHeaderField: "Retry-After") != nil {
                throw GitHubError(message: "API rate limit exceeded", status: code)
            }
            throw GitHubError(message: GitHubError.reason(from: data) ?? String(decoding: data, as: UTF8.self), status: code)
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

    /// Marks every thread read up to now, everywhere or in one repository.
    func markAllRead(repo: String? = nil) async throws {
        let stamp = ISO8601DateFormatter().string(from: Date())
        try await send(repo.map { "/repos/\($0)/notifications" } ?? "/notifications", method: "PUT",
                       body: ["last_read_at": stamp, "read": true])
    }

    /// Mutes a thread: new activity on it won't notify you.
    func unsubscribe(thread id: String) async throws {
        try await send("/notifications/threads/\(id)/subscription", method: "DELETE")
    }

    func markRead(thread id: String) async throws {
        try await send("/notifications/threads/\(id)", method: "PATCH")
    }

    func markRead(_ notification: GitHubNotification) async throws {
        try await send("/notifications/threads/\(notification.id)", method: "PATCH")
    }

    func markDone(_ notification: GitHubNotification) async throws {
        try await markDone(thread: notification.id)
    }

    func markDone(thread id: String) async throws {
        try await send("/notifications/threads/\(id)", method: "DELETE")
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

    func timeline(_ ref: IssueRef) async throws -> [TimelineEvent] {
        // ponytail: first 100 entries; follow `Link` pages for very long threads.
        try await get("/repos/\(ref.repo)/issues/\(ref.number)/timeline", query: ["per_page": "100"])
    }

    func closeIssue(_ ref: IssueRef) async throws {
        try await send("/repos/\(ref.repo)/issues/\(ref.number)", method: "PATCH", body: ["state": "closed"])
    }

    /// Whether you can triage (close, label) in a repository.
    func canTriage(_ repo: String) async throws -> Bool {
        struct Repository: Decodable {
            struct Permissions: Decodable { let triage: Bool?; let push: Bool?; let admin: Bool? }
            let permissions: Permissions?
        }
        let repository: Repository = try await get("/repos/\(repo)")
        let permissions = repository.permissions
        return permissions?.triage == true || permissions?.push == true || permissions?.admin == true
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

    /// The comment at an API URL, such as a notification's `latest_comment_url`.
    func comment(at url: URL) async throws -> IssueComment {
        try await get(url.path)
    }

    /// A job's plain-text log; only the last 5 MB of very long logs.
    func log(ofJob id: Int, repo: String) async throws -> String {
        let data = try await send("/repos/\(repo)/actions/jobs/\(id)/logs")
        return String(decoding: data.suffix(5_000_000), as: UTF8.self)
    }

    /// Annotations of a check run; an Actions job's id is its check run id.
    func annotations(checkRun id: Int, repo: String) async throws -> [Annotation] {
        try await get("/repos/\(repo)/check-runs/\(id)/annotations", query: ["per_page": "50"])
    }

    /// Readiness, size and body of one pull request in a single GraphQL call.
    func pullSummary(_ ref: IssueRef) async throws -> PullSummary {
        struct Login: Decodable { let login: String }
        struct Review: Decodable { let state: String; let author: Login? }
        struct Context: Decodable {
            let name: String?, status: String?, conclusion: String?  // CheckRun
            let context: String?, state: String?                     // StatusContext
        }
        struct Pull: Decodable {
            struct Nodes<T: Decodable>: Decodable { let nodes: [T] }
            struct Count: Decodable { let totalCount: Int }
            struct Commit: Decodable {
                struct Inner: Decodable {
                    struct Rollup: Decodable { let contexts: Nodes<Context> }
                    let statusCheckRollup: Rollup?
                }
                let commit: Inner
            }
            let body: String
            let author: Login?
            let additions: Int, deletions: Int, changedFiles: Int
            let headRefName: String, baseRefName: String
            let mergeable: String
            let mergeStateStatus: String?
            let reviewDecision: String?
            let latestOpinionatedReviews: Nodes<Review>
            let reviewRequests: Count
            let commits: Nodes<Commit>
        }
        struct Repository: Decodable { let pullRequest: Pull }
        struct Result: Decodable { let repository: Repository }
        let parts = ref.repo.split(separator: "/")
        let result: Result = try await graphQL("""
        query {
          repository(owner: "\(parts[0])", name: "\(parts[1])") {
            pullRequest(number: \(ref.number)) {
              body author { login } additions deletions changedFiles headRefName baseRefName
              mergeable mergeStateStatus reviewDecision
              latestOpinionatedReviews(first: 30) { nodes { state author { login } } }
              reviewRequests(first: 1) { totalCount }
              commits(last: 1) { nodes { commit { statusCheckRollup { contexts(first: 100) { nodes {
                ... on CheckRun { name status conclusion }
                ... on StatusContext { context state }
              } } } } } }
            }
          }
        }
        """)
        let pull = result.repository.pullRequest
        let reviews = pull.latestOpinionatedReviews.nodes
        let contexts = pull.commits.nodes.first?.commit.statusCheckRollup?.contexts.nodes ?? []
        return PullSummary(
            body: pull.body, author: pull.author?.login ?? "ghost",
            additions: pull.additions, deletions: pull.deletions, changedFiles: pull.changedFiles,
            headRef: pull.headRefName, baseRef: pull.baseRefName, mergeable: pull.mergeable,
            mergeState: pull.mergeStateStatus, reviewDecision: pull.reviewDecision,
            approvedBy: reviews.filter { $0.state == "APPROVED" }.compactMap(\.author?.login),
            changesRequestedBy: reviews.filter { $0.state == "CHANGES_REQUESTED" }.compactMap(\.author?.login),
            pendingReviewers: pull.reviewRequests.totalCount,
            checks: contexts.map { context in
                PullSummary.Check(name: context.name ?? context.context ?? "check",
                                  state: Readiness.checkState(status: context.status, conclusion: context.conclusion, state: context.state))
            })
    }

    // MARK: Reviews, merging, comments (redesign §7)

    enum ReviewEvent: String { case approve = "APPROVE", requestChanges = "REQUEST_CHANGES", comment = "COMMENT" }

    func submitReview(_ ref: IssueRef, event: ReviewEvent, body: String?) async throws {
        var fields: [String: Any] = ["event": event.rawValue]
        if let body, !body.isEmpty { fields["body"] = body }
        try await send("/repos/\(ref.repo)/pulls/\(ref.number)/reviews", method: "POST", body: fields)
    }

    /// Merges and, if asked, deletes the head branch afterwards.
    func merge(_ ref: IssueRef, method: String = "squash", deleteBranch: Bool) async throws {
        var branch: String?
        if deleteBranch { branch = try await pull(ref).head.ref }
        try await send("/repos/\(ref.repo)/pulls/\(ref.number)/merge", method: "PUT", body: ["merge_method": method])
        if let branch {
            try await send("/repos/\(ref.repo)/git/refs/heads/\(branch)", method: "DELETE")
        }
    }

    func addComment(_ ref: IssueRef, body: String) async throws {
        try await send("/repos/\(ref.repo)/issues/\(ref.number)/comments", method: "POST", body: ["body": body])
    }

    // MARK: Deployments

    func pendingDeployments(_ run: WorkflowRun) async throws -> [PendingDeployment] {
        try await get("/repos/\(run.repo)/actions/runs/\(run.id)/pending_deployments")
    }

    /// Approves or rejects every environment of the run the current user may review.
    func reviewDeployments(_ run: WorkflowRun, environments: [Int], approve: Bool, comment: String) async throws {
        try await send("/repos/\(run.repo)/actions/runs/\(run.id)/pending_deployments", method: "POST", body: [
            "environment_ids": environments, "state": approve ? "approved" : "rejected", "comment": comment,
        ])
    }

    // MARK: GraphQL

    private struct GraphQLResponse<T: Decodable>: Decodable {
        struct Message: Decodable { let message: String }
        let data: T?
        let errors: [Message]?
    }

    func graphQL<T: Decodable>(_ query: String, as type: T.Type = T.self) async throws -> T {
        let data = try await send("/graphql", method: "POST", body: ["query": query])
        let response: GraphQLResponse<T>
        do { response = try decoder.decode(GraphQLResponse<T>.self, from: data) } catch {
            throw GitHubError(message: "Failed to decode GraphQL response: \(error)")
        }
        guard let value = response.data else {
            throw GitHubError(message: response.errors?.map(\.message).joined(separator: "; ") ?? "Empty GraphQL response")
        }
        return value
    }

    /// Review decision, merge state and check rollup of your open pull requests, and which review requests name you
    /// directly (rather than a team you're on), keyed "owner/repo#number".
    func pullSignals() async throws -> (statuses: [String: PullStatus], direct: Set<String>) {
        struct Node: Decodable {
            struct Repository: Decodable { let nameWithOwner: String }
            struct Commits: Decodable {
                struct Item: Decodable {
                    struct Commit: Decodable {
                        struct Rollup: Decodable { let state: String }
                        let statusCheckRollup: Rollup?
                    }
                    let commit: Commit
                }
                let nodes: [Item]
            }
            let number: Int?
            let repository: Repository?
            let reviewDecision: String?
            let mergeStateStatus: String?
            let commits: Commits?
            var key: String? { number.flatMap { number in repository.map { "\($0.nameWithOwner)#\(number)" } } }
        }
        struct Search: Decodable { let nodes: [Node] }
        struct Result: Decodable { let authored: Search; let direct: Search }
        let fields = "number repository { nameWithOwner }"
        let result: Result = try await graphQL("""
        query {
          authored: search(query: "is:pr is:open archived:false author:@me", type: ISSUE, first: 50) {
            nodes { ... on PullRequest { \(fields) reviewDecision mergeStateStatus
              commits(last: 1) { nodes { commit { statusCheckRollup { state } } } } } }
          }
          direct: search(query: "is:pr is:open archived:false user-review-requested:@me", type: ISSUE, first: 50) {
            nodes { ... on PullRequest { \(fields) } }
          }
        }
        """)
        var statuses: [String: PullStatus] = [:]
        for node in result.authored.nodes {
            guard let key = node.key else { continue }
            statuses[key] = PullStatus(reviewDecision: node.reviewDecision, mergeState: node.mergeStateStatus,
                                       checks: .init(rollup: node.commits?.nodes.first?.commit.statusCheckRollup?.state))
        }
        return (statuses, Set(result.direct.nodes.compactMap(\.key)))
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

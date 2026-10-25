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

    /// Everything the pull request page and the Now queue show about one pull request, in one GraphQL call:
    /// readiness, size, reviewers, files and their viewed state, timed checks, and what you may do.
    func pullSummary(_ ref: IssueRef) async throws -> PullSummary {
        struct Login: Decodable { let login: String }
        struct Nodes<T: Decodable>: Decodable { let nodes: [T] }
        struct Count: Decodable { let totalCount: Int }
        struct Review: Decodable { let state: String; let author: Login? }
        struct Request: Decodable {
            struct Reviewer: Decodable { let login: String? }
            let asCodeOwner: Bool
            let requestedReviewer: Reviewer?
        }
        struct Closing: Decodable {
            struct Repository: Decodable { let name: String }
            let number: Int
            let repository: Repository
        }
        struct File: Decodable { let path: String; let additions: Int; let deletions: Int; let viewerViewedState: String? }
        struct Context: Decodable {
            struct Suite: Decodable { struct Run: Decodable { let databaseId: Int? }; let workflowRun: Run? }
            let name: String?, status: String?, conclusion: String?, startedAt: Date?, completedAt: Date?
            let databaseId: Int?, detailsUrl: URL?, checkSuite: Suite?           // CheckRun
            let context: String?, state: String?, createdAt: Date?, targetUrl: URL?  // StatusContext
        }
        struct Commit: Decodable {
            struct Inner: Decodable {
                struct Rollup: Decodable { let contexts: Nodes<Context> }
                let statusCheckRollup: Rollup?
            }
            let commit: Inner
        }
        struct AutoMerge: Decodable { let enabledBy: Login? }
        struct Pull: Decodable {
            let id: String, title: String, url: URL, body: String, isDraft: Bool, state: String, createdAt: Date
            let viewerDidAuthor: Bool
            let author: Login?
            let additions: Int, deletions: Int, changedFiles: Int
            let headRefName: String, baseRefName: String
            let mergeable: String
            let mergeStateStatus: String?
            let reviewDecision: String?
            let commitCount: Count
            let closingIssuesReferences: Nodes<Closing>?
            let autoMergeRequest: AutoMerge?
            let latestReviews: Nodes<Review>
            let reviewRequests: Nodes<Request>
            let files: Nodes<File>?
            let commits: Nodes<Commit>
        }
        struct Repository: Decodable {
            let viewerPermission: String?
            let squashMergeAllowed: Bool, mergeCommitAllowed: Bool, rebaseMergeAllowed: Bool, autoMergeAllowed: Bool
            let pullRequest: Pull
        }
        struct Result: Decodable { let repository: Repository }
        struct Teams: Decodable { struct Team: Decodable { let name: String }; let teams: [Team] }
        // Team names in GraphQL need the read:org scope, which a repo + notifications token lacks; REST has them.
        async let teams: Teams? = try? get("/repos/\(ref.repo)/pulls/\(ref.number)/requested_reviewers")
        let parts = ref.repo.split(separator: "/")
        let result: Result = try await graphQL("""
        query {
          repository(owner: "\(parts[0])", name: "\(parts[1])") {
            viewerPermission squashMergeAllowed mergeCommitAllowed rebaseMergeAllowed autoMergeAllowed
            pullRequest(number: \(ref.number)) {
              id title url body isDraft state createdAt viewerDidAuthor author { login }
              additions deletions changedFiles headRefName baseRefName mergeable mergeStateStatus reviewDecision
              commitCount: commits { totalCount }
              closingIssuesReferences(first: 3) { nodes { number repository { name } } }
              autoMergeRequest { enabledBy { login } }
              latestReviews(first: 30) { nodes { state author { login } } }
              reviewRequests(first: 30) { nodes { asCodeOwner requestedReviewer { ... on User { login } ... on Bot { login } } } }
              files(first: 100) { nodes { path additions deletions viewerViewedState } }
              commits(last: 1) { nodes { commit { statusCheckRollup { contexts(first: 100) { nodes {
                ... on CheckRun { name status conclusion startedAt completedAt databaseId detailsUrl
                                  checkSuite { workflowRun { databaseId } } }
                ... on StatusContext { context state createdAt targetUrl }
              } } } } } }
            }
          }
        }
        """)
        let repository = result.repository
        let pull = repository.pullRequest
        let contexts = pull.commits.nodes.first?.commit.statusCheckRollup?.contexts.nodes ?? []

        // Reviewers: everyone asked (with code owners marked), then everyone who reviewed, latest state each.
        // Team requests come back without a login; they take the REST team names in order.
        var teamNames = (await teams)?.teams.map { "@" + $0.name }.makeIterator()
        var reviewers: [PullSummary.Reviewer] = pull.reviewRequests.nodes.map { request in
            if let login = request.requestedReviewer?.login {
                return PullSummary.Reviewer(name: login, isTeam: false, state: .requested, isCodeOwner: request.asCodeOwner)
            }
            return PullSummary.Reviewer(name: teamNames?.next() ?? "A team", isTeam: true, state: .requested, isCodeOwner: request.asCodeOwner)
        }
        for review in pull.latestReviews.nodes {
            guard let name = review.author?.login, !reviewers.contains(where: { $0.name == name }) else { continue }
            let state: PullSummary.Reviewer.State = switch review.state {
            case "APPROVED": .approved
            case "CHANGES_REQUESTED": .changesRequested
            case "DISMISSED": .dismissed
            default: .commented
            }
            reviewers.append(PullSummary.Reviewer(name: name, isTeam: false, state: state, isCodeOwner: false))
        }

        let methods = [("squash", repository.squashMergeAllowed), ("merge", repository.mergeCommitAllowed),
                       ("rebase", repository.rebaseMergeAllowed)].filter(\.1).map(\.0)
        return PullSummary(
            body: pull.body, author: pull.author?.login ?? "ghost",
            additions: pull.additions, deletions: pull.deletions, changedFiles: pull.changedFiles,
            headRef: pull.headRefName, baseRef: pull.baseRefName, mergeable: pull.mergeable,
            mergeState: pull.mergeStateStatus, reviewDecision: pull.reviewDecision,
            approvedBy: reviewers.filter { $0.state == .approved }.map(\.name),
            changesRequestedBy: reviewers.filter { $0.state == .changesRequested }.map(\.name),
            pendingReviewers: reviewers.count { $0.state == .requested },
            checks: contexts.map { context in
                PullSummary.Check(name: context.name ?? context.context ?? "check",
                                  state: Readiness.checkState(status: context.status, conclusion: context.conclusion, state: context.state),
                                  startedAt: context.startedAt ?? context.createdAt, completedAt: context.completedAt,
                                  jobID: context.databaseId, runID: context.checkSuite?.workflowRun?.databaseId,
                                  url: context.detailsUrl ?? context.targetUrl)
            },
            id: pull.id, title: pull.title, url: pull.url, isDraft: pull.isDraft, state: pull.state, createdAt: pull.createdAt,
            viewerDidAuthor: pull.viewerDidAuthor, commitCount: pull.commitCount.totalCount,
            closingIssues: pull.closingIssuesReferences?.nodes.map { "\($0.repository.name) #\($0.number)" } ?? [],
            autoMergeBy: pull.autoMergeRequest.map { $0.enabledBy?.login ?? "someone" },
            reviewers: reviewers,
            files: pull.files?.nodes.map { .init(path: $0.path, additions: $0.additions, deletions: $0.deletions,
                                                 viewed: $0.viewerViewedState == "VIEWED") } ?? [],
            canWrite: ["ADMIN", "MAINTAIN", "WRITE"].contains(repository.viewerPermission ?? ""),
            mergeMethods: methods.isEmpty ? ["merge"] : methods,
            autoMergeAllowed: repository.autoMergeAllowed)
    }

    /// Changed files with their patches (REST): up to 300, GitHub's limit for patches in this list.
    func pullFiles(_ ref: IssueRef) async throws -> [PullFile] {
        var files: [PullFile] = []
        for page in 1...3 {
            let batch: [PullFile] = try await get("/repos/\(ref.repo)/pulls/\(ref.number)/files",
                                                  query: ["per_page": "100", "page": "\(page)"])
            files += batch
            if batch.count < 100 { break }
        }
        return files
    }

    /// Brings a branch that's behind its base up to date (merges the base in).
    func updateBranch(_ ref: IssueRef) async throws {
        try await send("/repos/\(ref.repo)/pulls/\(ref.number)/update-branch", method: "PUT", body: [:])
    }

    /// Re-runs one job (and the jobs that depend on it).
    func rerunJob(_ id: Int, repo: String) async throws {
        try await send("/repos/\(repo)/actions/jobs/\(id)/rerun", method: "POST")
    }

    func setViewed(_ path: String, viewed: Bool, pullID: String) async throws {
        struct Ignored: Decodable {}
        let mutation = viewed ? "markFileAsViewed" : "unmarkFileAsViewed"
        let escaped = path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let _: [String: Ignored?] = try await graphQL("""
        mutation { \(mutation)(input: { pullRequestId: "\(pullID)", path: "\(escaped)" }) { clientMutationId } }
        """)
    }

    /// Turns auto-merge on (with a merge method) or off.
    func setAutoMerge(_ enabled: Bool, pullID: String, method: String = "squash") async throws {
        struct Ignored: Decodable {}
        let mutation = enabled
            ? "enablePullRequestAutoMerge(input: { pullRequestId: \"\(pullID)\", mergeMethod: \(method.uppercased()) })"
            : "disablePullRequestAutoMerge(input: { pullRequestId: \"\(pullID)\" })"
        let _: [String: Ignored?] = try await graphQL("mutation { \(mutation) { clientMutationId } }")
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

    /// Readiness of every open pull request that involves you (checks, reviews, mergeability, size), and which
    /// review requests name you directly rather than a team you're on; keyed "owner/repo#number".
    func pullSignals() async throws -> (statuses: [String: PullStatus], direct: Set<String>) {
        struct StateCount: Decodable { let state: String; let count: Int }
        struct Node: Decodable {
            struct Repository: Decodable { let nameWithOwner: String }
            struct Nodes<T: Decodable>: Decodable { let nodes: [T] }
            struct Review: Decodable { let state: String }
            struct Commit: Decodable {
                struct Inner: Decodable {
                    struct Rollup: Decodable {
                        struct Contexts: Decodable {
                            let checkRunCountsByState: [StateCount]?
                            let statusContextCountsByState: [StateCount]?
                        }
                        let state: String
                        let contexts: Contexts?
                    }
                    let statusCheckRollup: Rollup?
                }
                let commit: Inner
            }
            let number: Int?
            let repository: Repository?
            let reviewDecision: String?
            let mergeStateStatus: String?
            let mergeable: String?
            let additions: Int?
            let deletions: Int?
            let latestOpinionatedReviews: Nodes<Review>?
            let commits: Nodes<Commit>?
            var key: String? { number.flatMap { number in repository.map { "\($0.nameWithOwner)#\(number)" } } }
        }
        struct Search: Decodable { let nodes: [Node] }
        struct Result: Decodable { let authored: Search; let requested: Search; let involved: Search; let direct: Search }
        let result: Result = try await graphQL("""
        query {
          authored: search(query: "is:pr is:open archived:false author:@me", type: ISSUE, first: 50) { nodes { ...Signals } }
          requested: search(query: "is:pr is:open archived:false review-requested:@me", type: ISSUE, first: 50) { nodes { ...Signals } }
          involved: search(query: "is:pr is:open archived:false involves:@me", type: ISSUE, first: 50) { nodes { ...Signals } }
          direct: search(query: "is:pr is:open archived:false user-review-requested:@me", type: ISSUE, first: 50) {
            nodes { ... on PullRequest { number repository { nameWithOwner } } }
          }
        }
        fragment Signals on PullRequest {
          number repository { nameWithOwner } reviewDecision mergeStateStatus mergeable additions deletions
          latestOpinionatedReviews(first: 20) { nodes { state } }
          commits(last: 1) { nodes { commit { statusCheckRollup { state contexts(first: 1) {
            checkRunCountsByState { state count } statusContextCountsByState { state count } } } } } }
        }
        """)
        var statuses: [String: PullStatus] = [:]
        for node in result.authored.nodes + result.requested.nodes + result.involved.nodes {
            guard let key = node.key, statuses[key] == nil else { continue }
            let rollup = node.commits?.nodes.first?.commit.statusCheckRollup
            let counts = CheckCounts(
                checkRuns: Dictionary((rollup?.contexts?.checkRunCountsByState ?? []).map { ($0.state, $0.count) }, uniquingKeysWith: +),
                statuses: Dictionary((rollup?.contexts?.statusContextCountsByState ?? []).map { ($0.state, $0.count) }, uniquingKeysWith: +))
            statuses[key] = PullStatus(
                reviewDecision: node.reviewDecision, mergeState: node.mergeStateStatus,
                checks: counts.total > 0 ? counts.overall : .init(rollup: rollup?.state),
                mergeable: node.mergeable, counts: counts,
                approvals: node.latestOpinionatedReviews?.nodes.count { $0.state == "APPROVED" } ?? 0,
                additions: node.additions ?? 0, deletions: node.deletions ?? 0)
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

import Foundation
import Testing
@testable import RepoRadar

// Fixtures decoded from GitHub-shaped JSON, so the tests exercise the same models the app does.

private let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}()

private func day(_ n: Int) -> String { String(format: "2026-01-%02dT00:00:00Z", n) }

private func run(_ id: Int, workflow: Int, name: String = "CI", branch: String = "main", status: String = "completed",
                 conclusion: String? = "failure", actor: String = "me", created: Int = 1, repo: String = "o/r") throws -> WorkflowRun {
    try decoder.decode(WorkflowRun.self, from: Data("""
    {"id": \(id), "name": "\(name)", "display_title": "t", "head_branch": "\(branch)", "event": "push",
     "status": "\(status)", "conclusion": \(conclusion.map { "\"\($0)\"" } ?? "null"),
     "workflow_id": \(workflow), "run_number": \(id), "html_url": "https://github.com/\(repo)/actions/runs/\(id)",
     "created_at": "\(day(created))", "updated_at": "\(day(created))", "run_started_at": null,
     "actor": {"login": "\(actor)"}, "repository": {"full_name": "\(repo)"}}
    """.utf8))
}

private func pull(_ number: Int, author: String = "alice", created: Int = 1, draft: Bool = false, repo: String = "o/r",
                  roles: Set<PRRole>, status: PullStatus? = nil, direct: Bool = false) throws -> PullItem {
    let pr = try decoder.decode(PullRequest.self, from: Data("""
    {"id": \(number * 100), "number": \(number), "title": "PR \(number)", "html_url": "https://github.com/\(repo)/pull/\(number)",
     "draft": \(draft), "user": {"login": "\(author)"}, "comments": 0, "created_at": "\(day(created))",
     "updated_at": "\(day(created))", "repository_url": "https://api.github.com/repos/\(repo)"}
    """.utf8))
    return PullItem(pr: pr, roles: roles, status: status, isDirectReview: direct)
}

private func thread(_ id: String, reason: String, type: String = "PullRequest", number: Int? = nil, title: String = "t",
                    unread: Bool = true, updated: Int = 1, repo: String = "o/r") throws -> GitHubNotification {
    let url = number.map { "\"https://api.github.com/repos/\(repo)/\(type == "Issue" ? "issues" : "pulls")/\($0)\"" } ?? "null"
    return try decoder.decode(GitHubNotification.self, from: Data("""
    {"id": "\(id)", "unread": \(unread), "reason": "\(reason)", "updated_at": "\(day(updated))",
     "subject": {"title": "\(title)", "type": "\(type)", "url": \(url)}, "repository": {"full_name": "\(repo)"}}
    """.utf8))
}

private let clean = PullStatus(reviewDecision: "APPROVED", mergeState: "CLEAN", checks: .passing)
private let changes = PullStatus(reviewDecision: "CHANGES_REQUESTED", mergeState: "BLOCKED", checks: .passing)

@Test func needsYouTiersAndOrder() throws {
    let input = NeedsYou.Input(
        login: "me",
        notifications: [try thread("m1", reason: "mention", type: "Issue", number: 50, updated: 4)],
        pulls: [
            try pull(10, created: 1, roles: [.reviewRequested]),                         // team review, oldest
            try pull(11, created: 5, roles: [.reviewRequested], direct: true),           // direct review
            try pull(12, author: "dependabot[bot]", created: 1, roles: [.reviewRequested], direct: true),  // bot: tier 4
            try pull(20, author: "me", created: 2, roles: [.authored], status: clean),   // can merge
            try pull(21, author: "me", created: 2, roles: [.authored], status: changes), // needs changes
            try pull(22, author: "me", created: 2, roles: [.authored], status: PullStatus(reviewDecision: nil, mergeState: "BLOCKED", checks: .pending)),
            try pull(30, created: 1, draft: true, roles: [.reviewRequested]),            // drafts never need you
        ],
        runsByRepo: ["o/r": [
            try run(1, workflow: 7, created: 3),                                  // your push failed on main
            try run(2, workflow: 8, actor: "someone", created: 3),                // someone else's: not yours
            try run(3, workflow: 9, branch: "feature", created: 3),               // not the default branch
            try run(4, workflow: 6, status: "waiting", conclusion: nil, created: 6),  // waiting for a deployment review
        ]],
        defaultBranches: ["o/r": "main"],
        pendingDeployments: [4: [PendingDeployment(environment: .init(id: 1, name: "production"), currentUserCanApprove: true)]]
    )
    let items = NeedsYou.build(input)
    #expect(items.map(\.id) == ["run:o/r:7", "deploy:4", "o/r#11", "o/r#10", "o/r#12", "o/r#20", "o/r#50", "o/r#21"])
    #expect(items.map(\.tier) == [1, 2, 3, 3, 4, 4, 5, 6])
}

@Test func needsYouDeduplicatesSubjectsAndAttachesThreads() throws {
    let input = NeedsYou.Input(
        login: "me",
        notifications: [
            try thread("r1", reason: "review_requested", number: 10, updated: 3),
            try thread("m1", reason: "mention", number: 10, updated: 4),           // same PR: one item, review wins
            try thread("c1", reason: "ci_activity", type: "CheckSuite", title: "CI workflow run failed for main branch"),
            try thread("c2", reason: "ci_activity", type: "CheckSuite", title: "Lint workflow run failed for main branch"),
        ],
        pulls: [try pull(10, created: 1, roles: [.reviewRequested, .mentioned])],
        runsByRepo: ["o/r": [try run(1, workflow: 7)]],
        defaultBranches: ["o/r": "main"]
    )
    let items = NeedsYou.build(input)
    #expect(items.count == 2)
    let review = try #require(items.first { $0.id == "o/r#10" })
    #expect(review.tier == 3)
    #expect(Set(review.notificationIDs) == ["r1", "m1"])
    // The review request's notification time is how long it has waited.
    #expect(review.since == ISO8601DateFormatter().date(from: day(3)))
    // The CI notification merges into the failed run of the same workflow and branch; the other stays in the Inbox.
    #expect(items.first { $0.id == "run:o/r:7" }?.notificationIDs == ["c1"])
}

@Test func needsYouVisibilityHonoursDoneSnoozeAndHidden() throws {
    let items = NeedsYou.build(NeedsYou.Input(pulls: [
        try pull(1, roles: [.reviewRequested]), try pull(2, roles: [.reviewRequested]), try pull(3, roles: [.reviewRequested]),
        try pull(4, roles: [.reviewRequested]),
    ]))
    let now = Date()
    let visible = NeedsYou.visible(items, done: [items[0].revision], snoozed: [items[1].id: now.addingTimeInterval(60),
                                                                               items[2].id: now.addingTimeInterval(-60)],
                                   hidden: [items[3].revision], now: now)
    // Done and hidden revisions are gone, the snoozed one waits, the expired snooze is back.
    #expect(visible.map(\.id) == [items[2].id])

    // New activity changes the revision, so a Done item comes back.
    let updated = try pull(1, created: 9, roles: [.reviewRequested])
    let rebuilt = NeedsYou.build(NeedsYou.Input(pulls: [updated]))
    #expect(NeedsYou.visible(rebuilt, done: [items[0].revision], snoozed: [:], hidden: []).count == 1)
}

// MARK: - Optimistic actions

/// Waits (up to 2 s) for `condition`: parallel tests share the main actor, so fixed sleeps are flaky.
@MainActor private func eventually(_ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(2)
    while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
}

@MainActor private final class Probe {
    var applied = 0, reverted = 0, committed = 0, completed = 0, failed = 0
}

@Test @MainActor func actionUndoneInsideWindowSendsNothing() async throws {
    let queue = ActionQueue(toasts: ToastCenter(), window: .milliseconds(80))
    let probe = Probe()
    queue.perform("Approved", apply: { probe.applied += 1 }, revert: { probe.reverted += 1 },
                  commit: { probe.committed += 1 })
    #expect(probe.applied == 1 && queue.canUndo)
    queue.undoLast()
    try await Task.sleep(for: .milliseconds(200))
    #expect(probe.committed == 0 && probe.reverted == 1 && !queue.canUndo)
}

@Test @MainActor func actionCommitsAfterWindow() async throws {
    let toasts = ToastCenter()
    let queue = ActionQueue(toasts: toasts, window: .milliseconds(50))
    let probe = Probe()
    queue.perform("Merged", apply: { probe.applied += 1 }, revert: { probe.reverted += 1 },
                  commit: { probe.committed += 1 }, completed: { probe.completed += 1 })
    #expect(probe.committed == 0)  // nothing is written during the window
    try await eventually { probe.completed == 1 }
    #expect(probe.committed == 1 && probe.completed == 1 && probe.reverted == 0 && !queue.canUndo)
}

@Test @MainActor func refusedActionRevertsAndRetries() async throws {
    let toasts = ToastCenter()
    let queue = ActionQueue(toasts: toasts, window: .milliseconds(30))
    let probe = Probe()
    var refuse = true
    queue.perform("Merged", apply: { probe.applied += 1 }, revert: { probe.reverted += 1 }, commit: {
        probe.committed += 1
        if refuse { throw GitHubError(message: "At least 2 approving reviews are required", status: 405) }
    }, failed: { probe.failed += 1 })
    try await eventually { probe.failed == 1 }
    #expect(probe.reverted == 1 && probe.failed == 1)
    #expect(toasts.current?.isError == true && toasts.current?.message == "At least 2 approving reviews are required")

    refuse = false
    toasts.current?.action?.perform()  // Retry: re-applies and writes at once
    try await eventually { probe.committed == 2 }
    #expect(probe.applied == 2 && probe.committed == 2 && probe.reverted == 1)
}

// MARK: - Sync and errors

@Test func syncCadenceStretchesForPollIntervalAndLowQuota() {
    let plenty = RateLimit(remaining: 4000, limit: 5000)
    let low = RateLimit(remaining: 200, limit: 5000)  // 4%
    #expect(SyncCadence.delay(.seconds(15), rateLimit: plenty) == .seconds(15))
    #expect(SyncCadence.delay(.seconds(15), rateLimit: low) == .seconds(120))
    #expect(SyncCadence.delay(.seconds(60), rateLimit: plenty, pollInterval: 90) == .seconds(90))
    #expect(SyncCadence.delay(.seconds(60), rateLimit: nil, pollInterval: 30) == .seconds(60))
}

@Test func githubErrorReasonIncludesDetails() {
    let review = Data(#"{"message": "Unprocessable Entity", "errors": ["Can not approve your own pull request"]}"#.utf8)
    #expect(GitHubError.reason(from: review) == "Unprocessable Entity: Can not approve your own pull request")
    let field = Data(#"{"message": "Validation Failed", "errors": [{"resource": "Issue", "code": "missing_field", "field": "body"}]}"#.utf8)
    #expect(GitHubError.reason(from: field) == "Validation Failed: missing_field body")
    #expect(GitHubError.reason(from: Data("not json".utf8)) == nil)
}

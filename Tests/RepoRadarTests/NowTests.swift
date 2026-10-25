import Foundation
import Testing
@testable import RepoRadar

private func summary(checks: [StatusKind], decision: String? = "REVIEW_REQUIRED", approved: [String] = [],
                     mergeable: String = "MERGEABLE", mergeState: String? = "BLOCKED", pending: Int = 2) -> PullSummary {
    PullSummary(body: "", author: "a", additions: 1, deletions: 1, changedFiles: 1, headRef: "feat", baseRef: "main",
                mergeable: mergeable, mergeState: mergeState, reviewDecision: decision, approvedBy: approved,
                changesRequestedBy: [], pendingReviewers: pending,
                checks: checks.enumerated().map { PullSummary.Check(name: "c\($0.offset)", state: $0.element) })
}

@Test func readinessStepsAndBlocker() {
    let running = Readiness.steps(summary(checks: [.success, .success, .running]), youAreRequested: true)
    #expect(running.map(\.text) == ["Checks 2/3 · 1 running", "Reviews 0/2 · you're next", "No conflicts", "Merge"])
    #expect(Readiness.blocker(running) == 0)

    let conflicted = Readiness.steps(summary(checks: [.success], decision: "APPROVED", approved: ["mika"], mergeable: "CONFLICTING"))
    #expect(conflicted.map(\.state) == [.success, .success, .failure, .skipped])
    #expect(Readiness.blocker(conflicted) == 2)

    let ready = Readiness.steps(summary(checks: [.success, .skipped], decision: "APPROVED", approved: ["mika", "jt"], mergeState: "CLEAN"))
    #expect(ready.map(\.text) == ["Checks 1/1", "Approved by mika, jt", "No conflicts", "Ready to merge"])
    #expect(Readiness.blocker(ready) == nil)

    #expect(Readiness.checkState(status: "COMPLETED", conclusion: "TIMED_OUT", state: nil) == .failure)
    #expect(Readiness.checkState(status: "QUEUED", conclusion: nil, state: nil) == .waiting)
    #expect(Readiness.checkState(status: nil, conclusion: nil, state: "PENDING") == .running)
}

private func run(_ id: Int, conclusion: String?, minutes: Double, status: String = "completed") throws -> WorkflowRun {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .iso8601
    let start = Date(timeIntervalSince1970: 1_700_000_000 + Double(id) * 10_000)
    let end = start.addingTimeInterval(minutes * 60)
    let iso = ISO8601DateFormatter()
    return try decoder.decode(WorkflowRun.self, from: Data("""
    {"id": \(id), "name": "CI", "display_title": "t", "head_branch": "main", "event": "push", "status": "\(status)",
     "conclusion": \(conclusion.map { "\"\($0)\"" } ?? "null"), "workflow_id": 1, "run_number": \(id),
     "html_url": "https://github.com/o/r/actions/runs/\(id)", "created_at": "\(iso.string(from: start))",
     "updated_at": "\(iso.string(from: end))", "run_started_at": "\(iso.string(from: start))",
     "actor": {"login": "me"}, "repository": {"full_name": "o/r"}}
    """.utf8))
}

@Test func passRateUsualDurationAndRemaining() throws {
    let runs = [
        try run(1, conclusion: "success", minutes: 3), try run(2, conclusion: "failure", minutes: 9),
        try run(3, conclusion: "success", minutes: 5), try run(4, conclusion: "cancelled", minutes: 1),
        try run(5, conclusion: "success", minutes: 4), try run(6, conclusion: "success", minutes: 6),
    ]
    // 4 passed, 1 failed; cancelled doesn't count.
    #expect(RunStats.passRate(runs) == 0.8)
    #expect(RunStats.passRate([]) == nil)
    #expect(RunStats.tone(ofPassRate: 0.8) == .amber)
    #expect(RunStats.tone(ofPassRate: 0.9) == .green)
    #expect(RunStats.tone(ofPassRate: 0.74) == .red)
    // Median of the successful runs: 3, 4, 5, 6 min → 4.5 min.
    #expect(RunStats.usualDuration(ofWorkflow: 1, in: runs) == 270)
    #expect(RunStats.usualDuration(ofWorkflow: 2, in: runs) == nil)
    #expect(RunStats.remainingText(elapsed: 60, usual: 270) == "about 4 min left")
    #expect(RunStats.remainingText(elapsed: 400, usual: 270) == "2 min slower than usual")
    #expect(RunStats.clock(130) == "2:10" && RunStats.clock(3725) == "1:02:05")
}

@Test func logExcerptKeepsErrorsWithContext() {
    let log = """
    2026-01-01T00:00:00.0000000Z line 1
    2026-01-01T00:00:01.0000000Z line 2
    2026-01-01T00:00:02.0000000Z line 3
    2026-01-01T00:00:03.0000000Z ##[error]first failure
    2026-01-01T00:00:04.0000000Z line 5
    2026-01-01T00:00:05.0000000Z ##[error]second failure
    line 7
    line 8
    line 9
    line 10
    line 11
    line 12
    ##[error]far away
    """
    let groups = LogExcerpt.errors(in: log)
    // The two nearby errors share one group (lines 2–8); the far one gets its own (11–13).
    #expect(groups.map { $0.map(\.number) } == [[2, 3, 4, 5, 6, 7, 8], [11, 12, 13]])
    #expect(groups[0][2] == LogExcerpt.Line(number: 4, text: "first failure", isError: true))
    #expect(groups[0][0].text == "line 2")
    #expect(LogExcerpt.errors(in: log, limit: 1).count == 1)
    #expect(LogExcerpt.errors(in: "all good").isEmpty)
}

@Test func jumpQueryAndResults() throws {
    let query = JumpQuery("repo:api #214 author:mika etag")
    #expect(query.repo == "api" && query.number == 214 && query.author == "mika" && query.words == ["etag"])
    #expect(JumpQuery("  ").isEmpty)

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .iso8601
    func pr(_ number: Int, _ title: String, _ repo: String, _ author: String) throws -> PullItem {
        PullItem(pr: try decoder.decode(PullRequest.self, from: Data("""
        {"id": \(number), "number": \(number), "title": "\(title)", "html_url": "https://github.com/\(repo)/pull/\(number)",
         "draft": false, "user": {"login": "\(author)"}, "comments": 0, "created_at": "2026-01-01T00:00:00Z",
         "updated_at": "2026-01-01T00:00:00Z", "repository_url": "https://api.github.com/repos/\(repo)"}
        """.utf8)), roles: [.reviewRequested])
    }
    let pulls = [try pr(214, "Add ETag caching", "lumen/api-gateway", "mika-chen"), try pr(57, "Glass toolbar", "me/RepoRadar", "me")]
    let repos = ["lumen/api-gateway", "me/RepoRadar"]

    let byNumber = Jump.results(JumpQuery("#214"), repos: repos, pulls: pulls, notifications: [], runs: [])
    #expect(byNumber.map(\.id) == ["pull:214"])
    let byWord = Jump.results(JumpQuery("radar"), repos: repos, pulls: pulls, notifications: [], runs: [])
    #expect(byWord.map(\.id) == ["repo:me/RepoRadar", "pull:57"])
    let byAuthor = Jump.results(JumpQuery("author:mika"), repos: repos, pulls: pulls, notifications: [], runs: [])
    #expect(byAuthor.map(\.id) == ["pull:214"])
    // Not loaded: offer GitHub.
    let remote = Jump.results(JumpQuery("repo:apple/swift #1"), repos: repos, pulls: pulls, notifications: [], runs: [])
    #expect(remote.map(\.webURL.absoluteString) == ["https://github.com/apple/swift/issues/1"])
}

@Test func snoozePresetsAndAges() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let wednesday = ISO8601DateFormatter().date(from: "2026-10-21T15:30:00Z")!
    let presets = SnoozePreset.dates(now: wednesday, calendar: calendar)
    let iso = ISO8601DateFormatter()
    #expect(presets.map { iso.string(from: $0.date) } == ["2026-10-21T16:30:00Z", "2026-10-22T09:00:00Z", "2026-10-26T09:00:00Z"])

    let now = Date()
    #expect(now.addingTimeInterval(-30).shortAge(now: now) == "now")
    #expect(now.addingTimeInterval(-720).shortAge(now: now) == "12m")
    #expect(now.addingTimeInterval(-3 * 86_400).shortAge(now: now) == "3d")
}

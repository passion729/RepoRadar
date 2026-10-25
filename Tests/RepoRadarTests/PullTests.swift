import Foundation
import Testing
@testable import RepoRadar

private func pull(_ number: Int, roles: Set<PRRole>, draft: Bool = false, direct: Bool = false, created: String = "2026-10-01T00:00:00Z",
                  updated: String = "2026-10-01T00:00:00Z", status: PullStatus? = nil) throws -> PullItem {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .iso8601
    let pr = try decoder.decode(PullRequest.self, from: Data("""
    {"id": \(number), "number": \(number), "title": "PR \(number)", "html_url": "https://github.com/o/r/pull/\(number)",
     "draft": \(draft), "user": {"login": "a"}, "comments": 0, "created_at": "\(created)", "updated_at": "\(updated)",
     "repository_url": "https://api.github.com/repos/o/r"}
    """.utf8))
    return PullItem(pr: pr, roles: roles, status: status, isDirectReview: direct)
}

@Test func checkCountsFromGraphQLStates() {
    let counts = CheckCounts(checkRuns: ["SUCCESS": 6, "FAILURE": 1, "IN_PROGRESS": 1, "SKIPPED": 2, "QUEUED": 1, "NEUTRAL": 1],
                             statuses: ["SUCCESS": 1, "PENDING": 1, "ERROR": 1])
    #expect(counts.passed == 8 && counts.failed == 2 && counts.running == 3 && counts.skipped == 2)
    #expect(counts.total == 13)
    #expect(counts.overall == .failing)
    #expect(CheckCounts(checkRuns: ["IN_PROGRESS": 2, "SUCCESS": 1], statuses: [:]).overall == .pending)
    #expect(CheckCounts().overall == .none)
}

@Test func readinessDotsAndTexts() {
    var running = CheckCounts()
    running.passed = 7
    running.running = 2
    let waiting = PullStatus(reviewDecision: "REVIEW_REQUIRED", mergeState: "BLOCKED", checks: .pending,
                             mergeable: "MERGEABLE", counts: running, approvals: 0)
    let dots = Readiness.dots(waiting)
    #expect(dots.map(\.state) == [.running, .waiting, .success])
    #expect(dots.map(\.text) == ["2 checks running", "0 approvals, review required", "no conflicts"])
    #expect(Readiness.blockerText(waiting) == "2 checks running")

    let conflicted = PullStatus(reviewDecision: nil, mergeState: "DIRTY", checks: .none, mergeable: "CONFLICTING")
    #expect(Readiness.dots(conflicted).map(\.state) == [.skipped, .skipped, .failure])
    #expect(Readiness.blockerText(conflicted) == "conflicts")

    let clean = PullStatus(reviewDecision: "APPROVED", mergeState: "CLEAN", checks: .passing, mergeable: "MERGEABLE")
    #expect(Readiness.blockerText(clean) == "ready to merge")
    #expect(Readiness.dots(nil).allSatisfy { $0.state == .skipped })
}

@Test func yourPullRequestTagTakesTheFirstMatch() throws {
    let ready = PullStatus(reviewDecision: "CHANGES_REQUESTED", mergeState: "CLEAN", checks: .failing)
    #expect(Readiness.yourTag(try pull(1, roles: [.authored], status: ready))! == ("Ready", .green))
    let failing = PullStatus(reviewDecision: "CHANGES_REQUESTED", mergeState: "BLOCKED", checks: .failing)
    #expect(Readiness.yourTag(try pull(2, roles: [.authored], status: failing))! == ("Checks failing", .red))
    let changes = PullStatus(reviewDecision: "CHANGES_REQUESTED", mergeState: "BLOCKED", checks: .passing)
    #expect(Readiness.yourTag(try pull(3, roles: [.authored], status: changes))! == ("Changes requested", .red))
    #expect(Readiness.yourTag(try pull(4, roles: [.authored], draft: true))! == ("Draft", .neutral))
    #expect(Readiness.yourTag(try pull(5, roles: [.authored])) == nil)
}

@Test func changeListOrderAndBars() {
    let files: [PullSummary.FileChange] = [
        .init(path: "Package.resolved", additions: 200, deletions: 100, viewed: false),
        .init(path: "Sources/A.swift", additions: 10, deletions: 5, viewed: false),
        .init(path: "Sources/B.swift", additions: 100, deletions: 20, viewed: true),
    ]
    #expect(ChangeList.sorted(files).map(\.path) == ["Sources/B.swift", "Sources/A.swift", "Package.resolved"])
    #expect(ChangeList.isGenerated("web/package-lock.json") && !ChangeList.isGenerated("Sources/Lock.swift"))
    // Scaled against the biggest file (300 lines): 120 pt for it, 6 pt for 15 lines.
    #expect(ChangeList.barWidth(files[0], in: files) == 120)
    #expect(ChangeList.barWidth(files[1], in: files) == 6)
}

@Test func checksTimelinePutsFailuresFirst() {
    let start = Date(timeIntervalSince1970: 0)
    let checks: [PullSummary.Check] = [
        .init(name: "lint", state: .success, startedAt: start),
        .init(name: "tests", state: .failure, startedAt: start.addingTimeInterval(60)),
        .init(name: "build", state: .running, startedAt: start.addingTimeInterval(30)),
        .init(name: "queued", state: .waiting),  // not started: not on the axis
    ]
    #expect(Readiness.timelineOrder(checks).map(\.name) == ["tests", "lint", "build"])
}

@Test func pullListsMatchAndSort() throws {
    let team = try pull(1, roles: [.reviewRequested], created: "2026-09-01T00:00:00Z")
    let direct = try pull(2, roles: [.reviewRequested], direct: true, created: "2026-10-01T00:00:00Z")
    let draft = try pull(3, roles: [.reviewRequested], draft: true)
    let mine = try pull(4, roles: [.authored, .mentioned])
    let assigned = try pull(5, roles: [.assigned])
    #expect(PullList.waiting.sorted([team, direct, draft].filter(PullList.waiting.matches)).map(\.number) == [2, 1])
    #expect([team, direct, draft, mine, assigned].filter(PullList.yours.matches).map(\.number) == [4])
    // Your own pull requests don't repeat under Mentioned; assigned ones show there.
    #expect([team, direct, draft, mine, assigned].filter(PullList.mentioned.matches).map(\.number) == [5])
}

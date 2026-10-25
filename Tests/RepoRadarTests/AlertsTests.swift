import Foundation
import Testing
@testable import RepoRadar

@Test func alertsOnlyForNewItemsOfTheFourKinds() throws {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .iso8601
    func pull(_ number: Int, roles: Set<PRRole>, status: PullStatus? = nil) throws -> PullItem {
        PullItem(pr: try decoder.decode(PullRequest.self, from: Data("""
        {"id": \(number), "number": \(number), "title": "PR \(number)", "html_url": "https://github.com/o/r/pull/\(number)",
         "draft": false, "user": {"login": "a"}, "comments": 0, "created_at": "2026-10-01T00:00:00Z",
         "updated_at": "2026-10-01T00:00:00Z", "repository_url": "https://api.github.com/repos/o/r"}
        """.utf8)), roles: roles, status: status)
    }
    let ready = PullStatus(reviewDecision: "APPROVED", mergeState: "CLEAN", checks: .passing)
    let items = NeedsYou.build(NeedsYou.Input(pulls: [try pull(1, roles: [.reviewRequested]), try pull(2, roles: [.reviewRequested]),
                                                      try pull(3, roles: [.authored], status: ready)]))
    #expect(items.count == 3)

    // The first load records everything without alerting; later only new revisions of alerting kinds count.
    let known: Set<String> = [items[0].revision]
    let fresh = Alerts.fresh(items, known: known, enabled: Alerts.Kind.allCases)
    #expect(fresh.map(\.id) == ["o/r#2"])  // #3 can merge: counts only, no alert
    #expect(Alerts.fresh(items, known: known, enabled: [.mention]).isEmpty)  // review alerts switched off

    let content = Alerts.content(for: fresh[0])
    #expect(content.kind == .review && content.title == "Review requested: PR 2" && content.subtitle == "o/r #2")
    #expect(Alerts.categories.map(\.identifier).sorted() == ["DEPLOYMENT", "OPEN", "PUSH_FAILED"])
}

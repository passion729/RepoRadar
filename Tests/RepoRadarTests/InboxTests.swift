import Foundation
import Testing
@testable import RepoRadar

private let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}()

private func thread(_ id: String, _ title: String, reason: String = "subscribed", type: String = "PullRequest",
                    number: Int? = 1, repo: String = "o/r", updated: String, unread: Bool = true) throws -> GitHubNotification {
    let url = number.map { "\"https://api.github.com/repos/\(repo)/pulls/\($0)\"" } ?? "null"
    return try decoder.decode(GitHubNotification.self, from: Data("""
    {"id": "\(id)", "unread": \(unread), "reason": "\(reason)", "updated_at": "\(updated)", "last_read_at": null,
     "subject": {"title": "\(title)", "type": "\(type)", "url": \(url), "latest_comment_url": null},
     "repository": {"full_name": "\(repo)"}}
    """.utf8))
}

@Test func inboxReasonTagsAndFilters() throws {
    let mention = try thread("1", "t", reason: "mention", updated: "2026-10-21T10:00:00Z")
    let ciFailed = try thread("2", "CI workflow run failed for main branch", reason: "ci_activity", type: "CheckSuite", number: nil,
                              updated: "2026-10-21T10:00:00Z")
    let ciPassed = try thread("3", "CI workflow run succeeded for main branch", reason: "ci_activity", type: "CheckSuite", number: nil,
                              updated: "2026-10-21T10:00:00Z")
    let release = try thread("4", "v1.0", type: "Release", number: nil, updated: "2026-10-21T10:00:00Z", unread: false)
    let odd = try thread("5", "t", reason: "your_activity", updated: "2026-10-21T10:00:00Z")
    #expect(Inbox.tag(mention) == ("Mention", .purple))
    #expect(Inbox.tag(ciFailed) == ("CI failed", .red))
    #expect(Inbox.tag(ciPassed) == ("CI passed", .green))
    #expect(Inbox.tag(release) == ("Release", .green))
    #expect(Inbox.tag(odd).text == "your activity")  // unknown reasons show as GitHub names them

    #expect(InboxFilter.mentions.matches(mention) && !InboxFilter.mentions.matches(ciFailed))
    #expect(InboxFilter.ci.matches(ciPassed))
    #expect(!InboxFilter.unread.matches(release) && InboxFilter.all.matches(release))
    #expect(InboxFilter.participating.matches(mention) && !InboxFilter.participating.matches(release))
}

@Test func inboxSectionsBundleBotsAndGroup() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.firstWeekday = 2  // Monday
    let now = ISO8601DateFormatter().date(from: "2026-10-22T15:00:00Z")!  // a Thursday
    let threads = [
        try thread("a", "Rate limit regression", reason: "mention", number: 9, updated: "2026-10-22T14:00:00Z"),
        try thread("b", "Bump swift-markdown from 0.4.0 to 0.5.0", number: 33, repo: "o/kit", updated: "2026-10-22T12:00:00Z"),
        try thread("c", "Fix tests", number: 34, repo: "o/kit", updated: "2026-10-22T11:00:00Z"),
        try thread("d", "chore(deps): update node", number: 35, repo: "o/web", updated: "2026-10-22T10:00:00Z"),
        try thread("e", "Add ETag caching", reason: "review_requested", number: 214, updated: "2026-10-20T10:00:00Z"),
        try thread("f", "Old thing", number: 2, updated: "2026-09-01T10:00:00Z"),
    ]
    // #34 is by dependabot (known from the pull request list), so it joins the bundle despite its title.
    let authors = ["o/kit#34": "dependabot[bot]", "o/r#9": "jtorres"]
    let sections = Inbox.sections(threads, grouping: .time, authors: authors, now: now, calendar: calendar)
    #expect(sections.map(\.title) == ["Today", "Earlier this week", "Older"])
    #expect(sections[0].entries.map(\.id) == ["a", "bots:b"])
    #expect(sections[0].entries[1].threads.map(\.id) == ["b", "c", "d"])
    #expect(sections[1].entries.map(\.id) == ["e"])

    let byRepo = Inbox.sections(threads, grouping: .repository, authors: authors, now: now, calendar: calendar)
    #expect(byRepo.map(\.title) == ["o/r", "o/kit", "o/web"])
    #expect(byRepo[2].entries.map(\.id) == ["d"])  // a lone bot thread isn't bundled

    #expect(Inbox.time(threads[0].updatedAt, now: now, calendar: calendar) == "1h")
}

@Test func inboxSearchSyntax() throws {
    let note = try thread("1", "Rate limit regression", reason: "mention", number: 1093, repo: "lumen/web", updated: "2026-10-21T10:00:00Z")
    let authors = ["lumen/web#1093": "jtorres"]
    #expect(Inbox.matches(note, JumpQuery("repo:web reason:mention"), authors: authors))
    #expect(Inbox.matches(note, JumpQuery("author:jt rate"), authors: authors))
    #expect(Inbox.matches(note, JumpQuery("#1093"), authors: authors))
    #expect(!Inbox.matches(note, JumpQuery("reason:review"), authors: authors))
    #expect(!Inbox.matches(note, JumpQuery("author:mika"), authors: authors))
}

@Test func labelTextReachesContrast() {
    for hex: UInt32 in [0xFFFF00, 0x0E8A16, 0xD73A4A, 0x000000, 0xFFFFFF, 0x7057FF] {
        #expect(LabelColors.contrast(LabelColors.text(hex, dark: false), 0xFFFFFF) >= 4.5)
        #expect(LabelColors.contrast(LabelColors.text(hex, dark: true), 0x1E1E22) >= 4.5)
    }
    #expect(LabelColors.text(0x000000, dark: false) == 0x000000)  // already readable: unchanged
}

@Test func markdownCleansSimpleHTML() {
    #expect(MarkdownBlock.cleanHTML(#"<p><a href="https://x.dev/1">ZXD-146</a></p><br/>Done"#) == "[ZXD-146](https://x.dev/1)\nDone")
    #expect(MarkdownBlock.cleanHTML("<!-- hidden -->Shown <img src=\"a.png\">") == "Shown ")
}

@Test func threadEntriesSkipNoise() throws {
    let issue = try decoder.decode(IssueDetail.self, from: Data("""
    {"title": "t", "body": "Hi", "state": "open", "user": {"login": "jt"}, "labels": [], "created_at": "2026-10-20T10:00:00Z",
     "html_url": "https://github.com/o/r/issues/1", "draft": null, "pull_request": null}
    """.utf8))
    let timeline = try decoder.decode([TimelineEvent].self, from: Data("""
    [{"id": 1, "event": "subscribed", "actor": {"login": "jt"}, "created_at": "2026-10-20T10:00:00Z"},
     {"id": 2, "event": "labeled", "actor": {"login": "mika"}, "created_at": "2026-10-20T11:00:00Z", "label": {"name": "p1", "color": "d73a4a"}},
     {"id": 3, "event": "commented", "user": {"login": "mika"}, "created_at": "2026-10-20T12:00:00Z", "body": "@me look", "author_association": "MEMBER"},
     {"event": "cross-referenced", "actor": {"login": "mika"}, "created_at": "2026-10-20T13:00:00Z",
      "source": {"issue": {"number": 214, "title": "Fix", "html_url": "https://github.com/o/api/pull/214", "state": "open",
                           "pull_request": {"merged_at": null}, "repository": {"full_name": "o/api"}}}}]
    """.utf8))
    let entries = ThreadEntry.build(issue: issue, timeline: timeline)
    #expect(entries.map(\.id) == ["opened", "e2", "e3", "i3"])
    #expect(entries.map(\.isComment) == [true, false, true, false])
}

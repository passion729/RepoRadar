import Foundation

/// Inbox filters (I2).
enum InboxFilter: String, CaseIterable, Identifiable {
    case unread, participating, mentions, ci, all

    var id: Self { self }

    var title: String {
        switch self {
        case .unread: "Unread"
        case .participating: "Participating"
        case .mentions: "Mentions"
        case .ci: "CI"
        case .all: "All"
        }
    }

    func matches(_ thread: GitHubNotification) -> Bool {
        switch self {
        case .unread: thread.unread
        // Threads you take part in, as opposed to ones you only watch.
        case .participating: !["subscribed", "manual", "ci_activity", "security_alert"].contains(thread.reason)
        case .mentions: ["mention", "team_mention"].contains(thread.reason)
        case .ci: thread.reason == "ci_activity" || thread.subject.type == "CheckSuite"
        case .all: true
        }
    }
}

enum InboxGrouping: String, CaseIterable, Identifiable {
    case time, repository

    var id: Self { self }
    var title: String { self == .time ? "By Time" : "By Repository" }
}

/// A list entry: one thread, or several bot threads bundled into one row (I5).
enum InboxEntry: Identifiable, Hashable {
    case thread(GitHubNotification)
    case bots([GitHubNotification])

    var id: String {
        switch self {
        case .thread(let thread): thread.id
        case .bots(let threads): "bots:" + (threads.first?.id ?? "")
        }
    }

    var threads: [GitHubNotification] {
        switch self {
        case .thread(let thread): [thread]
        case .bots(let threads): threads
        }
    }
}

struct InboxSection: Identifiable, Hashable {
    let title: String
    let entries: [InboxEntry]
    var id: String { title }
}

enum Inbox {
    /// The reason chip (I3): GitHub's reason in a word, with its color. Unknown reasons show as GitHub names them.
    static func tag(_ thread: GitHubNotification) -> (text: String, tone: Tone) {
        if thread.subject.type == "Release" { return ("Release", .green) }
        switch thread.reason {
        case "mention", "team_mention": return ("Mention", .purple)
        case "review_requested": return ("Review", .blue)
        case "approval_requested": return ("Approval", .amber)
        case "ci_activity":
            let title = thread.title.lowercased()
            if title.contains("failed") || title.contains("failure") { return ("CI failed", .red) }
            if title.contains("succeeded") || title.contains("success") { return ("CI passed", .green) }
            return ("CI", .neutral)
        case "comment": return ("Comment", .neutral)
        case "state_change": return ("Closed", .neutral)
        case "assign": return ("Assigned", .neutral)
        case "author": return ("Author", .neutral)
        case "security_alert": return ("Security", .red)
        case "subscribed", "manual": return ("Watching", .neutral)
        default: return (thread.reason.replacingOccurrences(of: "_", with: " "), .neutral)
        }
    }

    /// Bot threads: a known bot authored the pull request, or the title is a dependency bump.
    // ponytail: notifications don't say who acted; authors come from loaded pull requests, otherwise titles
    // like "Bump x from 1 to 2". Fetch each thread's latest comment if the guess proves too loose.
    static func isBot(_ thread: GitHubNotification, authors: [String: String], bots: Set<String> = Config.botLogins) -> Bool {
        if let key = thread.subjectKey, let author = authors[key] { return bots.contains(author) }
        return thread.title.firstMatch(of: /^(Bump |Update dependency |(chore|build|fix)\(deps(-dev)?\): )/) != nil
    }

    /// Newest first, grouped by time (Today / Earlier this week / Older) or by repository; within a section,
    /// bot threads collapse into one entry where the newest of them sits.
    static func sections(_ threads: [GitHubNotification], grouping: InboxGrouping, authors: [String: String],
                         now: Date = Date(), calendar: Calendar = .current) -> [InboxSection] {
        let sorted = threads.sorted { ($0.updatedAt, $0.id) > ($1.updatedAt, $1.id) }
        let groups: [(String, [GitHubNotification])]
        switch grouping {
        case .time:
            let today = calendar.startOfDay(for: now)
            let week = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
            let buckets = [("Today", sorted.filter { $0.updatedAt >= today }),
                           ("Earlier this week", sorted.filter { $0.updatedAt < today && $0.updatedAt >= week }),
                           ("Older", sorted.filter { $0.updatedAt < min(week, today) })]
            groups = buckets.filter { !$0.1.isEmpty }
        case .repository:
            var order: [String] = []
            var byRepo: [String: [GitHubNotification]] = [:]
            for thread in sorted {
                if byRepo[thread.repo] == nil { order.append(thread.repo) }
                byRepo[thread.repo, default: []].append(thread)
            }
            groups = order.map { ($0, byRepo[$0]!) }
        }
        return groups.map { title, threads in
            let bots = threads.filter { isBot($0, authors: authors) }
            var entries: [InboxEntry] = []
            for thread in threads {
                if bots.count > 1, bots.contains(thread) {
                    if thread == bots.first { entries.append(.bots(bots)) }
                } else {
                    entries.append(.thread(thread))
                }
            }
            return InboxSection(title: title, entries: entries)
        }
    }

    /// Search (I2): `repo:`, `reason:`, `author:` and words in the title or repository.
    static func matches(_ thread: GitHubNotification, _ query: JumpQuery, authors: [String: String]) -> Bool {
        if let repo = query.repo, !thread.repo.localizedCaseInsensitiveContains(repo) { return false }
        if let reason = query.reason, !thread.reason.localizedCaseInsensitiveContains(reason),
           !tag(thread).text.localizedCaseInsensitiveContains(reason) { return false }
        if let author = query.author,
           !(thread.subjectKey.flatMap { authors[$0] }?.localizedCaseInsensitiveContains(author) ?? false) { return false }
        if let number = query.number, thread.ref?.number != number { return false }
        return query.words.allSatisfy { thread.title.localizedCaseInsensitiveContains($0) || thread.repo.localizedCaseInsensitiveContains($0) }
    }

    /// "12m" today, "Thu" this week, "Oct 3" before that.
    static func time(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return date.shortAge(now: now) }
        if let week = calendar.dateInterval(of: .weekOfYear, for: now), week.contains(date) {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

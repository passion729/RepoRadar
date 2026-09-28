import SwiftUI

struct Repo: Decodable, Hashable {
    let fullName: String
    let pushedAt: Date?
    let archived: Bool
}

struct Actor: Decodable, Hashable { let login: String }
struct RepoRef: Decodable, Hashable { let fullName: String }

// MARK: - Actions

struct WorkflowRunsPage: Decodable {
    let workflowRuns: [WorkflowRun]
}

struct WorkflowRun: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let displayTitle: String
    let headBranch: String?
    let event: String
    let status: String?
    let conclusion: String?
    let workflowId: Int
    let runNumber: Int
    let htmlUrl: URL
    let createdAt: Date
    let updatedAt: Date
    let runStartedAt: Date?
    let actor: Actor?
    let repository: RepoRef
    /// Workflow file, e.g. `.github/workflows/deploy.yml` (dynamic workflows may add an `@ref` suffix).
    let path: String?
    let headSha: String?

    var repo: String { repository.fullName }
    var workflowName: String { name ?? "Workflow \(workflowId)" }
    var branchName: String { headBranch ?? "—" }
    var actorName: String { actor?.login ?? "—" }
    var state: RunState { RunState(status: status, conclusion: conclusion) }

    var duration: TimeInterval {
        let end = state.isActive ? Date() : updatedAt
        return end.timeIntervalSince(runStartedAt ?? createdAt)
    }
}

struct JobsPage: Decodable {
    let jobs: [WorkflowJob]
}

struct WorkflowJob: Decodable, Identifiable, Hashable {
    struct Step: Decodable, Identifiable, Hashable {
        let number: Int
        let name: String
        let status: String?
        let conclusion: String?
        var id: Int { number }
        var state: RunState { RunState(status: status, conclusion: conclusion) }
    }

    let id: Int
    let name: String
    let status: String?
    let conclusion: String?
    let startedAt: Date?
    let completedAt: Date?
    let htmlUrl: URL?
    let steps: [Step]?

    var state: RunState { RunState(status: status, conclusion: conclusion) }

    var duration: TimeInterval? {
        guard let startedAt else { return nil }
        return (completedAt ?? Date()).timeIntervalSince(startedAt)
    }
}

/// Declared in severity order, so sorting by state puts failures first.
enum RunState: Comparable {
    case failure, running, queued, success, cancelled, skipped

    init(status: String?, conclusion: String?) {
        switch status {
        case "in_progress": self = .running
        case "completed":
            switch conclusion {
            case "success": self = .success
            case "failure", "timed_out", "startup_failure", "action_required": self = .failure
            case "cancelled": self = .cancelled
            default: self = .skipped
            }
        default: self = .queued  // queued / waiting / pending / requested
        }
    }

    var isActive: Bool { self == .running || self == .queued }
    var canRerunFailedJobs: Bool { self == .failure || self == .cancelled }

    var symbol: String {
        switch self {
        case .failure: "xmark.circle.fill"
        case .running: "play.circle.fill"
        case .queued: "clock.fill"
        case .success: "checkmark.circle.fill"
        case .cancelled: "stop.circle"
        case .skipped: "slash.circle"
        }
    }

    var color: Color {
        switch self {
        case .failure: .red
        case .running: .orange
        case .success: .green
        default: .secondary
        }
    }

    var label: String {
        switch self {
        case .failure: "Failed"
        case .running: "Running"
        case .queued: "Queued"
        case .success: "Succeeded"
        case .cancelled: "Cancelled"
        case .skipped: "Skipped"
        }
    }
}

extension Array where Element == WorkflowRun {
    /// The newest run of each workflow — i.e. each workflow's current status.
    func latestPerWorkflow() -> [WorkflowRun] {
        var seen = Set<Int>()
        return sorted { $0.createdAt > $1.createdAt }.filter { seen.insert($0.workflowId).inserted }
    }

    /// Worst state wins: failure > running/queued > success.
    var overall: RunState? {
        if isEmpty { return nil }
        if contains(where: { $0.state == .failure }) { return .failure }
        if contains(where: { $0.state.isActive }) { return .running }
        return .success
    }
}

// MARK: - Issues & pull requests

/// Points at an issue or pull request; both share GitHub's issue number space.
struct IssueRef: Hashable {
    let repo: String
    let number: Int
    let isPullRequest: Bool
}

struct SearchPage<Item: Decodable>: Decodable {
    let items: [Item]
}

/// A pull request as returned by the issue search API.
struct PullRequest: Decodable, Identifiable, Hashable {
    let id: Int
    let number: Int
    let title: String
    let htmlUrl: URL
    let draft: Bool?
    let user: Actor
    let comments: Int
    let createdAt: Date
    let updatedAt: Date
    let repositoryUrl: URL

    var repo: String { repositoryUrl.pathComponents.suffix(2).joined(separator: "/") }
    var ref: IssueRef { IssueRef(repo: repo, number: number, isPullRequest: true) }
    var isDraft: Bool { draft ?? false }
}

/// How a pull request involves you. Each maps to one search qualifier.
enum PRRole: String, CaseIterable, Identifiable {
    case reviewRequested, authored, assigned, mentioned

    var id: Self { self }

    var title: String {
        switch self {
        case .reviewRequested: "Review Requested"
        case .authored: "Authored"
        case .assigned: "Assigned"
        case .mentioned: "Mentioned"
        }
    }

    var shortTitle: String {
        self == .reviewRequested ? "Reviews" : title
    }

    var qualifier: String {
        switch self {
        case .reviewRequested: "review-requested:@me"
        case .authored: "author:@me"
        case .assigned: "assignee:@me"
        case .mentioned: "mentions:@me"
        }
    }
}

struct PullItem: Identifiable, Hashable {
    let pr: PullRequest
    var roles: Set<PRRole>

    var id: Int { pr.id }
    var title: String { pr.title }
    var repo: String { pr.repo }
    var author: String { pr.user.login }
    var comments: Int { pr.comments }
    var isDraftRank: Int { pr.isDraft ? 1 : 0 }
    var number: Int { pr.number }
    var updatedAt: Date { pr.updatedAt }
    var rolesSummary: String { PRRole.allCases.filter(roles.contains).map(\.title).joined(separator: ", ") }
}

struct IssueLabel: Decodable, Hashable {
    let name: String
    let color: String
}

struct IssueDetail: Decodable, Hashable {
    struct PullLink: Decodable, Hashable { let mergedAt: Date? }

    let title: String
    let body: String?
    let state: String
    let user: Actor
    let labels: [IssueLabel]
    let createdAt: Date
    let htmlUrl: URL
    let draft: Bool?
    let pullRequest: PullLink?

    var stateLabel: String {
        if pullRequest?.mergedAt != nil { return "Merged" }
        if draft == true { return "Draft" }
        return state == "open" ? "Open" : "Closed"
    }

    var stateColor: Color {
        switch stateLabel {
        case "Merged": .purple
        case "Open": .green
        case "Closed": .red
        default: .secondary
        }
    }
}

struct PullDetail: Decodable, Hashable {
    struct Branch: Decodable, Hashable {
        let ref: String
        let sha: String
    }

    let head: Branch
    let base: Branch
    let additions: Int
    let deletions: Int
    let changedFiles: Int
    let requestedReviewers: [Actor]
}

struct IssueComment: Decodable, Identifiable, Hashable {
    let id: Int
    let user: Actor
    let body: String?
    let createdAt: Date
}

// MARK: - Notifications

/// A GitHub notification thread (GET /notifications).
struct GitHubNotification: Decodable, Identifiable, Hashable {
    struct Subject: Decodable, Hashable {
        let title: String
        let type: String  // PullRequest, Issue, Release, Discussion, CheckSuite, Commit…
        let url: URL?
    }

    let id: String
    var unread: Bool
    let reason: String
    let updatedAt: Date
    let subject: Subject
    let repository: RepoRef

    var repo: String { repository.fullName }
    var title: String { subject.title }
    /// Unread first when sorting ascending.
    var unreadRank: Int { unread ? 0 : 1 }

    /// The issue or pull request this thread is about, parsed from `…/repos/{owner}/{repo}/{issues|pulls}/{n}`.
    var ref: IssueRef? {
        guard let url = subject.url, subject.type == "PullRequest" || subject.type == "Issue" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 5, parts[0] == "repos", let number = Int(parts[4]) else { return nil }
        return IssueRef(repo: "\(parts[1])/\(parts[2])", number: number, isPullRequest: subject.type == "PullRequest")
    }

    /// For CI notifications, which carry no subject URL: the workflow and branch named in the title,
    /// e.g. "Release workflow run failed for v1.0.0 branch".
    var workflowRunHint: (workflow: String, branch: String)? {
        guard subject.type == "CheckSuite",
              let match = title.firstMatch(of: /^(.+) workflow run \w+ for (.+) branch$/) else { return nil }
        return (String(match.1), String(match.2))
    }

    var webURL: URL {
        let repoURL = URL(string: "https://github.com/\(repo)")!
        if let ref {
            return repoURL.appending(path: "\(ref.isPullRequest ? "pull" : "issues")/\(ref.number)")
        }
        switch subject.type {
        case "Release": return repoURL.appending(path: "releases")
        case "Discussion": return repoURL.appending(path: "discussions")
        case "CheckSuite": return repoURL.appending(path: "actions")
        default: return repoURL
        }
    }

    var typeLabel: String {
        switch subject.type {
        case "PullRequest": "Pull Request"
        case "CheckSuite": "CI"
        default: subject.type
        }
    }

    var symbol: String {
        switch subject.type {
        case "PullRequest": "arrow.triangle.pull"
        case "Issue": "smallcircle.filled.circle"
        case "Release": "tag"
        case "Discussion": "bubble.left.and.bubble.right"
        case "CheckSuite": "bolt.circle"
        case "Commit": "point.topleft.down.to.point.bottomright.curvepath"
        default: "bell"
        }
    }

    var reasonLabel: String {
        switch reason {
        case "review_requested": "Review requested"
        case "mention", "team_mention": "Mentioned"
        case "assign": "Assigned"
        case "author": "Author"
        case "comment": "Comment"
        case "state_change": "State changed"
        case "ci_activity": "CI activity"
        case "subscribed", "manual": "Watching"
        default: reason.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

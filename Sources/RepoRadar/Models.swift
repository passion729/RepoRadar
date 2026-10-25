import SwiftUI

struct Repo: Decodable, Hashable {
    let fullName: String
    let pushedAt: Date?
    let archived: Bool
    let defaultBranch: String?
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
    /// Paused until someone reviews a protected environment.
    var isAwaitingApproval: Bool { status == "waiting" }
    /// Changes when the run does (a re-run, or a run that finishes), so viewing it again is needed.
    var seenKey: String { "run-\(id)-\(updatedAt.timeIntervalSince1970)" }

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
    /// Merge readiness, known for your own pull requests.
    var status: PullStatus?
    /// The review request names you, not only a team you're on.
    var isDirectReview = false

    var id: Int { pr.id }
    var title: String { pr.title }
    var repo: String { pr.repo }
    var author: String { pr.user.login }
    var comments: Int { pr.comments }
    var number: Int { pr.number }
    var updatedAt: Date { pr.updatedAt }
    /// Changes with any new activity on the pull request, so viewing it again is needed.
    var seenKey: String { "pr-\(pr.id)-\(pr.updatedAt.timeIntervalSince1970)" }
}

/// "owner/repo#number": the same key for an issue, a pull request and their notification threads.
func subjectKey(_ repo: String, _ number: Int) -> String { "\(repo)#\(number)" }

/// What GitHub's GraphQL API says about a pull request's readiness.
struct PullStatus: Hashable {
    enum Checks: Hashable {
        case passing, failing, pending, none

        init(rollup: String?) {
            switch rollup {
            case "SUCCESS": self = .passing
            case "FAILURE", "ERROR": self = .failing
            case "PENDING", "EXPECTED": self = .pending
            default: self = .none
            }
        }
    }

    /// APPROVED, CHANGES_REQUESTED or REVIEW_REQUIRED.
    let reviewDecision: String?
    /// CLEAN, BLOCKED, BEHIND, DIRTY, UNSTABLE, HAS_HOOKS, DRAFT or UNKNOWN.
    let mergeState: String?
    let checks: Checks
    /// MERGEABLE, CONFLICTING or UNKNOWN.
    var mergeable: String?
    var counts = CheckCounts()
    var approvals = 0
    var additions = 0
    var deletions = 0

    /// Checks pass, enough approvals, no conflicts.
    var isReadyToMerge: Bool { mergeState == "CLEAN" || mergeState == "HAS_HOOKS" }
    var needsChanges: Bool { reviewDecision == "CHANGES_REQUESTED" || checks == .failing }
}

/// Checks of a commit by outcome, from GraphQL's `checkRunCountsByState` / `statusContextCountsByState`.
struct CheckCounts: Hashable {
    var passed = 0, failed = 0, running = 0, skipped = 0
    var total: Int { passed + failed + running }

    init() {}

    init(checkRuns: [String: Int], statuses: [String: Int]) {
        for (state, count) in checkRuns {
            switch state {
            case "SUCCESS", "NEUTRAL": passed += count
            case "FAILURE", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE": failed += count
            case "SKIPPED", "STALE", "CANCELLED": skipped += count
            default: running += count  // QUEUED, IN_PROGRESS, PENDING, WAITING, REQUESTED
            }
        }
        for (state, count) in statuses {
            switch state {
            case "SUCCESS": passed += count
            case "FAILURE", "ERROR": failed += count
            default: running += count  // PENDING, EXPECTED
            }
        }
    }

    var overall: PullStatus.Checks {
        failed > 0 ? .failing : running > 0 ? .pending : passed > 0 ? .passing : .none
    }
}

/// An environment a run is waiting on (GET …/pending_deployments).
struct PendingDeployment: Decodable, Hashable {
    struct Environment: Decodable, Hashable {
        let id: Int
        let name: String?
    }

    let environment: Environment
    let currentUserCanApprove: Bool
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
    var comments: Int?

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

/// What the Now queue and the pull request page show about one pull request (GraphQL).
struct PullSummary: Hashable {
    struct Check: Hashable {
        let name: String
        let state: StatusKind
        var startedAt: Date?
        var completedAt: Date?
        /// The Actions job (check run) id, and its run.
        var jobID: Int?
        var runID: Int?
        var url: URL?
    }

    struct Reviewer: Hashable {
        enum State: Hashable { case requested, approved, changesRequested, commented, dismissed }
        let name: String
        let isTeam: Bool
        var state: State
        var isCodeOwner: Bool
    }

    struct FileChange: Hashable {
        let path: String
        let additions: Int
        let deletions: Int
        var viewed: Bool
    }

    var body: String
    var author: String
    var additions: Int
    var deletions: Int
    var changedFiles: Int
    var headRef: String
    var baseRef: String
    /// MERGEABLE, CONFLICTING or UNKNOWN.
    var mergeable: String
    var mergeState: String?
    var reviewDecision: String?
    var approvedBy: [String]
    var changesRequestedBy: [String]
    var pendingReviewers: Int
    var checks: [Check]

    /// GraphQL node id, for mutations (viewed files, auto-merge).
    var id = ""
    var title = ""
    var url: URL?
    var isDraft = false
    /// OPEN, CLOSED or MERGED.
    var state = "OPEN"
    var createdAt: Date?
    var viewerDidAuthor = false
    var commitCount = 0
    /// Issues this pull request closes, as "repo #n".
    var closingIssues: [String] = []
    /// Who turned on auto-merge, when it's on.
    var autoMergeBy: String?
    var reviewers: [Reviewer] = []
    var files: [FileChange] = []
    /// You can merge (write access or more).
    var canWrite = false
    /// Allowed merge methods in GitHub's order: squash, merge, rebase.
    var mergeMethods: [String] = ["squash"]
    var autoMergeAllowed = false
}

/// A changed file with its unified diff (REST; `patch` is missing for binary or very large files).
struct PullFile: Decodable, Hashable, Identifiable {
    let filename: String
    let status: String
    let additions: Int
    let deletions: Int
    let patch: String?
    var id: String { filename }
}

/// A check run annotation: a failing test or lint error with its location.
struct Annotation: Decodable, Hashable {
    let path: String?
    let startLine: Int?
    let annotationLevel: String?
    let title: String?
    let message: String
}

/// One entry of an issue or pull request timeline (GET …/issues/{n}/timeline): a comment or an event.
struct TimelineEvent: Decodable, Hashable {
    struct Label: Decodable, Hashable { let name: String; let color: String }
    struct Rename: Decodable, Hashable { let from: String; let to: String }
    struct Source: Decodable, Hashable {
        struct Issue: Decodable, Hashable {
            struct PullLink: Decodable, Hashable { let mergedAt: Date? }
            struct Repository: Decodable, Hashable { let fullName: String }
            let number: Int
            let title: String
            let htmlUrl: URL
            let state: String
            let pullRequest: PullLink?
            let repository: Repository?
        }
        let issue: Issue?
    }

    let id: Int?
    /// commented, labeled, unlabeled, cross-referenced, closed, reopened, merged, review_requested, reviewed,
    /// committed, assigned, renamed, head_ref_deleted…
    let event: String?
    let actor: Actor?
    let user: Actor?
    let createdAt: Date?
    let submittedAt: Date?
    let body: String?
    let authorAssociation: String?
    let label: Label?
    let source: Source?
    let state: String?
    let message: String?
    let requestedReviewer: Actor?
    let assignee: Actor?
    let rename: Rename?

    var who: String { (user ?? actor)?.login ?? "someone" }
    var date: Date? { createdAt ?? submittedAt }
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
        /// The comment that triggered the thread (API URL), e.g. the one that @-mentions you.
        let latestCommentUrl: URL?
    }

    let id: String
    var unread: Bool
    let reason: String
    /// Overridden for a snoozed thread when it comes back, so it sorts to the top.
    var updatedAt: Date
    /// When you last read the thread; comments after it are new.
    let lastReadAt: Date?
    let subject: Subject
    let repository: RepoRef

    var repo: String { repository.fullName }
    var title: String { subject.title }
    /// Unread first when sorting ascending.
    var unreadRank: Int { unread ? 0 : 1 }

    var subjectKey: String? { ref.map { RepoRadar.subjectKey($0.repo, $0.number) } }

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

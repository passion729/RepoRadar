import Foundation

/// One thing that needs you (G3), built from notifications, pull request searches, Actions runs and
/// deployment reviews. The same pull request, run or thread appears once, whichever sources mention it.
struct NeedsYouItem: Identifiable, Hashable {
    enum Kind: Hashable {
        /// A run you triggered failed on the default branch.
        case pushFailed(WorkflowRun)
        /// A run waits for you to approve its environments.
        case deployment(WorkflowRun, environments: [PendingDeployment])
        case review(PullItem, direct: Bool, bot: Bool)
        /// Your pull request can merge: checks pass, enough approvals, no conflicts.
        case mergeable(PullItem)
        case mention(GitHubNotification)
        /// Your pull request has changes requested or failing checks.
        case changesRequested(PullItem)
    }

    enum Category: CaseIterable { case review, ciAndDeploys, mention, yourPullRequest }

    /// Stable per subject: "owner/repo#12", "run:owner/repo:workflow", "deploy:run".
    let id: String
    let kind: Kind
    /// 1 (most urgent) … 6.
    let tier: Int
    /// Orders items inside a tier before age: a direct review request ahead of a team one.
    let subrank: Int
    /// How long it has waited; older first within a tier.
    let since: Date
    /// Unique to the subject and its latest activity, so Done hides only what you've seen.
    let revision: String
    /// Threads about the same subject; handling the item marks them done.
    var notificationIDs: [String]

    var repo: String {
        switch kind {
        case .pushFailed(let run), .deployment(let run, _): run.repo
        case .review(let pull, _, _), .mergeable(let pull), .changesRequested(let pull): pull.repo
        case .mention(let note): note.repo
        }
    }

    var title: String {
        switch kind {
        case .pushFailed(let run): "\(run.workflowName) failed on \(run.branchName)"
        case .deployment(let run, _): "\(run.workflowName) is waiting for approval"
        case .review(let pull, _, _), .mergeable(let pull), .changesRequested(let pull): pull.title
        case .mention(let note): note.title
        }
    }

    var url: URL {
        switch kind {
        case .pushFailed(let run), .deployment(let run, _): run.htmlUrl
        case .review(let pull, _, _), .mergeable(let pull), .changesRequested(let pull): pull.pr.htmlUrl
        case .mention(let note): note.webURL
        }
    }

    var category: Category {
        switch kind {
        case .pushFailed, .deployment: .ciAndDeploys
        case .review: .review
        case .mention: .mention
        case .mergeable, .changesRequested: .yourPullRequest
        }
    }
}

enum NeedsYou {
    struct Input {
        var login: String?
        var notifications: [GitHubNotification] = []
        var pulls: [PullItem] = []
        var runsByRepo: [String: [WorkflowRun]] = [:]
        var defaultBranches: [String: String] = [:]
        /// Pending environments per waiting run id.
        var pendingDeployments: [Int: [PendingDeployment]] = [:]
        var bots: Set<String> = Config.botLogins
    }

    /// Every item, deduplicated and in queue order: by tier, then direct before team, then longest waiting.
    static func build(_ input: Input) -> [NeedsYouItem] {
        let threads = Dictionary(grouping: input.notifications.filter { $0.subjectKey != nil }, by: { $0.subjectKey! })
        var candidates: [NeedsYouItem] = []

        // 1 · your push failed (latest run of each workflow on the default branch)
        for (repo, runs) in input.runsByRepo {
            guard let login = input.login, let branch = input.defaultBranches[repo] else { continue }
            for run in runs.filter({ $0.headBranch == branch }).latestPerWorkflow()
            where run.state == .failure && run.actor?.login == login {
                candidates.append(NeedsYouItem(id: "run:\(repo):\(run.workflowId)", kind: .pushFailed(run), tier: 1, subrank: 0,
                                               since: run.updatedAt, revision: "run-\(run.id)-\(run.updatedAt.timeIntervalSince1970)",
                                               notificationIDs: []))
            }
        }

        // 2 · deployments waiting for you
        for run in input.runsByRepo.values.joined() where run.isAwaitingApproval {
            let environments = (input.pendingDeployments[run.id] ?? []).filter(\.currentUserCanApprove)
            guard !environments.isEmpty else { continue }
            candidates.append(NeedsYouItem(id: "deploy:\(run.id)", kind: .deployment(run, environments: environments), tier: 2,
                                           subrank: 0, since: run.updatedAt, revision: "deploy-\(run.id)", notificationIDs: []))
        }

        for pull in input.pulls where !pull.pr.isDraft {
            let key = subjectKey(pull.repo, pull.number)
            let revision = "\(key)@\(pull.pr.updatedAt.timeIntervalSince1970)-"
            // 3 · review requests; bots drop a tier
            if pull.roles.contains(.reviewRequested) {
                let bot = input.bots.contains(pull.author)
                let requested = threads[key]?.first { $0.reason == "review_requested" }?.updatedAt ?? pull.pr.createdAt
                candidates.append(NeedsYouItem(id: key, kind: .review(pull, direct: pull.isDirectReview, bot: bot),
                                               tier: bot ? 4 : 3, subrank: pull.isDirectReview ? 0 : 1, since: requested,
                                               revision: revision + "review", notificationIDs: []))
            }
            // 4 · your pull request can merge · 6 · it needs changes
            if pull.roles.contains(.authored), let status = pull.status {
                if status.isReadyToMerge {
                    candidates.append(NeedsYouItem(id: key, kind: .mergeable(pull), tier: 4, subrank: 0, since: pull.updatedAt,
                                                   revision: revision + "merge", notificationIDs: []))
                } else if status.needsChanges {
                    candidates.append(NeedsYouItem(id: key, kind: .changesRequested(pull), tier: 6, subrank: 0, since: pull.updatedAt,
                                                   revision: revision + "changes", notificationIDs: []))
                }
            }
        }

        // 5 · unread mentions
        for note in input.notifications where note.unread && ["mention", "team_mention"].contains(note.reason) {
            candidates.append(NeedsYouItem(id: note.subjectKey ?? "thread:\(note.id)", kind: .mention(note), tier: 5, subrank: 0,
                                           since: note.updatedAt, revision: "n-\(note.id)-\(note.updatedAt.timeIntervalSince1970)",
                                           notificationIDs: [note.id]))
        }

        // One item per subject: the most urgent wins.
        var byID: [String: NeedsYouItem] = [:]
        for item in candidates {
            if let existing = byID[item.id], (existing.tier, existing.subrank) <= (item.tier, item.subrank) { continue }
            byID[item.id] = item
        }

        // Attach the threads about each item: the review request or mention for a pull request,
        // and the CI notification for a failed run (matched by workflow and branch named in its title).
        for note in input.notifications {
            let id: String?
            if let key = note.subjectKey {
                id = key
            } else if let hint = note.workflowRunHint {
                id = byID.values.first { item in
                    guard case .pushFailed(let run) = item.kind else { return false }
                    return run.repo == note.repo && run.workflowName == hint.workflow && run.branchName == hint.branch
                }?.id
            } else {
                id = nil
            }
            guard let id, byID[id] != nil, !byID[id]!.notificationIDs.contains(note.id) else { continue }
            byID[id]!.notificationIDs.append(note.id)
        }

        return byID.values.sorted { ($0.tier, $0.subrank, $0.since, $0.id) < ($1.tier, $1.subrank, $1.since, $1.id) }
    }

    /// Drops what the user has handled: done (this revision), snoozed until later, or waiting on an undo window.
    static func visible(_ items: [NeedsYouItem], done: Set<String>, snoozed: [String: Date], hidden: Set<String>,
                        now: Date = Date()) -> [NeedsYouItem] {
        items.filter { item in
            !done.contains(item.revision) && !hidden.contains(item.revision) && (snoozed[item.id] ?? .distantPast) <= now
        }
    }
}

import AppKit
import UserNotifications

@MainActor @Observable
final class AppState {
    static let shared = AppState()

    // MARK: Actions

    /// Recent runs (newest first) of every repo that has any.
    private(set) var runsByRepo: [String: [WorkflowRun]] = [:] {
        didSet {
            latestRuns = runsByRepo.values.flatMap { $0.latestPerWorkflow() }
            announceStartedRuns(before: oldValue)
            announceFinishedRuns(before: oldValue)
        }
    }
    /// Current status of every workflow across all repos. Stored rather than computed
    /// so views that read it many times per body don't re-derive it.
    private(set) var latestRuns: [WorkflowRun] = []
    /// Runs awaiting the user's confirmation before they're cancelled.
    var pendingCancel: [WorkflowRun] = []

    // MARK: Inbox & pull requests

    /// Every thread GitHub returned. `notifications` is what the app shows: without threads an action is about
    /// to mark done or that are snoozed, read where you read them, and snoozed threads that came back as unread.
    private(set) var inbox: [GitHubNotification] = []
    var notifications: [GitHubNotification] {
        guard !hiddenThreads.isEmpty || !snoozedThreads.isEmpty || !readThreads.isEmpty else { return inbox }
        let now = Date()
        return inbox.compactMap { thread in
            guard !hiddenThreads.contains(thread.id) else { return nil }
            var thread = thread
            if let until = snoozedThreads[thread.id] {
                guard until <= now else { return nil }
                thread.unread = true  // back from snooze: unread, at the top
                thread.updatedAt = max(thread.updatedAt, until)
            }
            if readThreads.contains(thread.id) { thread.unread = false }
            return thread
        }
    }
    /// Threads snoozed until a date (I4). Local only; when the time comes they're unread again.
    private(set) var snoozedThreads = UserDefaults.standard.dictionary(forKey: "snoozedThreads") as? [String: Date] ?? [:] {
        didSet { defaults.set(snoozedThreads, forKey: "snoozedThreads") }
    }
    /// Threads read here that GitHub may not report as read yet (an undoable Mark All Read, or one in flight).
    private(set) var readThreads: Set<String> = []
    /// Unsent replies per thread (I9).
    var drafts = UserDefaults.standard.dictionary(forKey: "replyDrafts") as? [String: String] ?? [:] {
        didSet { defaults.set(drafts, forKey: "replyDrafts") }
    }
    /// Bumped after a comment lands, so open threads reload their timeline.
    private(set) var timelineVersion = 0
    /// Open pull requests involving you, without ones just merged here (they leave the list at once, P6).
    var pulls: [PullItem] {
        hiddenPulls.isEmpty ? allPulls : allPulls.filter { !hiddenPulls.contains($0.id) }
    }
    private var allPulls: [PullItem] = []
    private var hiddenPulls: Set<Int> = []
    /// Environments waiting runs are blocked on, per run id.
    private(set) var pendingDeployments: [Int: [PendingDeployment]] = [:]
    /// `seenKey`s of runs and pull requests the user has viewed; those stop counting as needing attention.
    private(set) var seen = Set(UserDefaults.standard.stringArray(forKey: "seenItems") ?? []) {
        didSet { defaults.set(Array(seen), forKey: "seenItems") }
    }

    // MARK: Needs you (G3) and optimistic actions (G4)

    let toasts: ToastCenter
    let actions: ActionQueue
    /// Revisions marked Done; an item comes back when something new happens on it.
    private(set) var doneItems = Set(UserDefaults.standard.stringArray(forKey: "doneItems") ?? []) {
        didSet { defaults.set(Array(doneItems), forKey: "doneItems") }
    }
    /// Item ids snoozed until a date.
    private(set) var snoozedItems = UserDefaults.standard.dictionary(forKey: "snoozedItems") as? [String: Date] ?? [:] {
        didSet { defaults.set(snoozedItems, forKey: "snoozedItems") }
    }
    /// Revisions and threads hidden while an action waits out its undo window or GitHub catches up.
    private(set) var hiddenItems: Set<String> = []
    private(set) var hiddenThreads: Set<String> = []
    /// Item ids whose last action GitHub refused; the row is marked until it's acted on again.
    private(set) var failedItems: Set<String> = []

    // MARK: Account & status

    private(set) var isRefreshing = false
    private(set) var lastUpdated: Date?
    private(set) var login: String?
    private(set) var rateLimit: RateLimit?
    /// GitHub's requested notification poll interval, in seconds.
    private(set) var pollInterval: Int?
    /// The token's OAuth scopes, once a response has reported them (fine-grained tokens report none).
    private(set) var tokenScopes: Set<String>?
    private(set) var hasToken = Keychain.load() != nil
    var error: String?
    /// Why the last sync failed, if it did; cleared by the next successful one.
    private(set) var failure: SyncFailure?
    /// Set by the menu bar extra to jump the main window to a page.
    var requestedPage: Page?
    /// Something a page should select once it appears (set with `navigate(to:select:)`).
    var requestedSelection: SelectionRequest?

    // MARK: Scope

    /// Each watched repository's default branch, from the repository list.
    private(set) var defaultBranches: [String: String] = [:]
    /// Repositories pinned to the sidebar, in the user's order (at most `maxPins`).
    private(set) var pinnedRepos = UserDefaults.standard.stringArray(forKey: "pinnedRepos") ?? [] {
        didSet { defaults.set(pinnedRepos, forKey: "pinnedRepos") }
    }
    static let maxPins = 8
    /// Repositories and owners (users or organizations) left out of every list and count (G7).
    private(set) var excludedRepos = UserDefaults.standard.stringArray(forKey: "excludedRepos") ?? [] {
        didSet { defaults.set(excludedRepos, forKey: "excludedRepos") }
    }
    private(set) var excludedOwners = UserDefaults.standard.stringArray(forKey: "excludedOwners") ?? [] {
        didSet { defaults.set(excludedOwners, forKey: "excludedOwners") }
    }
    /// System alerts stay quiet until then.
    private(set) var alertsPausedUntil = UserDefaults.standard.object(forKey: "alertsPausedUntil") as? Date {
        didSet { defaults.set(alertsPausedUntil, forKey: "alertsPausedUntil") }
    }
    /// The pinned repository every page is filtered to, or nil for all.
    var scopeRepo: String?

    @ObservationIgnored private var loops: [Task<Void, Never>] = []
    /// Ids seen at the last refresh; nil until the first load so launching doesn't notify about old items.
    @ObservationIgnored private var knownFailures: Set<Int>?
    @ObservationIgnored private var knownUnread: Set<String>?

    private let defaults = UserDefaults.standard
    private let client = GitHubClient.shared
    private var canNotify: Bool { Bundle.main.bundleIdentifier != nil }  // `swift run` has no bundle

    init() {
        let toasts = ToastCenter()
        self.toasts = toasts
        actions = ActionQueue(toasts: toasts)
        defaults.register(defaults: ["refreshMinutes": 5, "lookbackDays": 30, "notifyFailures": true, "notifyInbox": true, "notifyOwnActivity": false,
                                      "notifyFinishedRuns": true, "notifyStartedRuns": true, "doneAfterReply": true])
    }

    var repos: [String] { runsByRepo.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } }
    var failingCount: Int { latestRuns.count(where: needsAttention) }
    var unreadCount: Int { notifications.count(where: \.unread) }
    var reviewRequestCount: Int { pulls.count(where: needsAttention) }

    var syncStatus: SyncStatus {
        SyncStatus(hasToken: hasToken, isRefreshing: isRefreshing, failure: failure, rateLimit: rateLimit)
    }

    // MARK: Scoped counts (sidebar)

    func inScope(_ repo: String) -> Bool { scopeRepo == nil || scopeRepo == repo }

    /// Everything that needs you, across every repository, in queue order.
    // ponytail: rebuilt on each read (a few hundred records); cache it if profiling shows the queue in body time.
    var allNeedsYou: [NeedsYouItem] {
        let input = NeedsYou.Input(login: login, notifications: notifications, pulls: pulls, runsByRepo: runsByRepo,
                                   defaultBranches: defaultBranches, pendingDeployments: pendingDeployments)
        return NeedsYou.visible(NeedsYou.build(input), done: doneItems, snoozed: snoozedItems, hidden: hiddenItems)
    }
    /// The queue within the sidebar's repository scope.
    var needsYou: [NeedsYouItem] { allNeedsYou.filter { inScope($0.repo) } }
    var needsYouCount: Int { needsYou.count }
    var scopedUnreadCount: Int { notifications.count { $0.unread && inScope($0.repo) } }
    /// Pull requests waiting on your review plus your own.
    var scopedPullCount: Int {
        pulls.count { inScope($0.repo) && ($0.roles.contains(.authored) || ($0.roles.contains(.reviewRequested) && !$0.pr.isDraft)) }
    }
    var scopedFailingCount: Int { latestRuns.count { inScope($0.repo) && $0.state == .failure } }

    /// Runs in progress within scope (not those paused for a deployment review): yours first, then oldest first.
    var runningRuns: [WorkflowRun] {
        runsByRepo.values.joined()
            .filter { $0.state.isActive && !$0.isAwaitingApproval && inScope($0.repo) }
            .sorted { ($0.actor?.login == login ? 0 : 1, $0.createdAt) < ($1.actor?.login == login ? 0 : 1, $1.createdAt) }
    }

    /// The median of the workflow's last 10 successful runs.
    func usualDuration(of run: WorkflowRun) -> TimeInterval? {
        RunStats.usualDuration(ofWorkflow: run.workflowId, in: runsByRepo[run.repo] ?? [])
    }

    /// Switches the main window to `page` and asks it to select something.
    func navigate(to page: Page, select selection: SelectionRequest? = nil) {
        requestedSelection = selection
        requestedPage = page
    }

    /// A repository's runs on its default branch, oldest first.
    func defaultBranchRuns(of repo: String) -> [WorkflowRun] {
        let runs = runsByRepo[repo] ?? []
        let branch = defaultBranches[repo]
        return runs.filter { branch == nil || $0.headBranch == branch }.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: Exclusions

    func isExcluded(_ repo: String) -> Bool {
        Self.isExcluded(repo, repos: excludedRepos, owners: excludedOwners)
    }

    nonisolated static func isExcluded(_ repo: String, repos: [String], owners: [String]) -> Bool {
        repos.contains(repo) || owners.contains(String(repo.prefix { $0 != "/" }))
    }

    func setExcluded(_ repo: String, _ excluded: Bool) {
        excludedRepos.removeAll { $0 == repo }
        if excluded { excludedRepos.append(repo) }
        exclusionsChanged(reload: !excluded)
    }

    func setExcluded(owner: String, _ excluded: Bool) {
        excludedOwners.removeAll { $0 == owner }
        if excluded { excludedOwners.append(owner) }
        exclusionsChanged(reload: !excluded)
    }

    /// Drops newly excluded data right away; bringing a repository back needs a refresh.
    private func exclusionsChanged(reload: Bool) {
        runsByRepo = runsByRepo.filter { !isExcluded($0.key) }
        allPulls.removeAll { isExcluded($0.repo) }
        inbox.removeAll { isExcluded($0.repo) }
        pinnedRepos.removeAll(where: isExcluded)
        if let scopeRepo, isExcluded(scopeRepo) { self.scopeRepo = nil }
        publishBadge()
        if reload { Task { await refresh() } }
    }

    // MARK: Alerts

    var alertsPaused: Bool { (alertsPausedUntil ?? .distantPast) > Date() }

    func pauseAlerts(for duration: TimeInterval) { alertsPausedUntil = Date().addingTimeInterval(duration) }
    func resumeAlerts() { alertsPausedUntil = nil }

    // MARK: Pins

    func pin(_ repo: String) {
        guard !pinnedRepos.contains(repo), pinnedRepos.count < Self.maxPins else { return }
        pinnedRepos.append(repo)
    }

    func unpin(_ repo: String) {
        pinnedRepos.removeAll { $0 == repo }
        if scopeRepo == repo { scopeRepo = nil }
    }

    /// Moves a pinned repository to where `target` is.
    func movePin(_ repo: String, to target: String) {
        guard repo != target, let from = pinnedRepos.firstIndex(of: repo), let to = pinnedRepos.firstIndex(of: target) else { return }
        pinnedRepos.move(fromOffsets: [from], toOffset: to > from ? to + 1 : to)
    }

    /// A failure or review request that hasn't been viewed yet.
    func needsAttention(_ run: WorkflowRun) -> Bool { run.state == .failure && !seen.contains(run.seenKey) }
    func needsAttention(_ pull: PullItem) -> Bool { pull.roles.contains(.reviewRequested) && !seen.contains(pull.seenKey) }

    // MARK: - Refreshing

    func start() {
        if canNotify {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
        loops.forEach { $0.cancel() }
        // Sync cadence (G2). Unchanged GETs are free 304s thanks to ETags; every delay stretches to
        // 2 minutes when less than 5% of the quota is left.
        loops = [
            // Everything, including the repository list, every few minutes (Settings ▸ General).
            Task {
                while !Task.isCancelled {
                    await refresh()
                    let minutes = max(1, defaults.integer(forKey: "refreshMinutes"))
                    try? await Task.sleep(for: .seconds(minutes * 60))
                }
            },
            // Notifications every minute, or as rarely as GitHub's X-Poll-Interval asks.
            Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: SyncCadence.delay(.seconds(60), rateLimit: rateLimit, pollInterval: pollInterval))
                    await refreshInbox()
                }
            },
            // Pull requests and their readiness every minute.
            Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: SyncCadence.delay(.seconds(60), rateLimit: rateLimit))
                    await refreshPulls()
                }
            },
            // Runs: those in progress every 15 s while any run, and repositories with a run in the last day
            // every minute, to catch new runs.
            Task {
                var tick = 0
                while !Task.isCancelled {
                    let active = runsByRepo.values.contains { $0.contains(where: \.state.isActive) }
                    try? await Task.sleep(for: SyncCadence.delay(active ? Config.activeRunRefresh : .seconds(60), rateLimit: rateLimit))
                    tick += 1
                    await watchRuns(includeRecent: !active || tick % 4 == 0)
                }
            },
        ]
    }

    func refresh() async {
        guard !isRefreshing else { return }
        hasToken = Keychain.load() != nil
        guard hasToken else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            if login == nil { login = try await client.login() }
            async let runs = fetchRuns()
            async let inbox = client.notifications()
            async let prs = fetchPulls()
            let ((newRuns, branches), newInbox, newPulls) = try await (runs, inbox, prs)
            defaultBranches = branches
            runsByRepo = newRuns.filter { !isExcluded($0.key) }
            pendingDeployments = await fetchPendingDeployments()
            allPulls = newPulls.filter { !isExcluded($0.repo) }
            hiddenPulls.formIntersection(allPulls.map(\.id))
            let current = Set(newRuns.values.joined().map(\.seenKey) + newPulls.map(\.seenKey))
            if !seen.isSubset(of: current) { seen.formIntersection(current) }  // forget items that are gone
            apply(newInbox)
            forgetHandledItems()
            lastUpdated = Date()
            rateLimit = await client.rateLimit
            tokenScopes = await client.scopes
            error = nil
            failure = nil
            publishFailures()
        } catch {
            self.error = error.localizedDescription
            failure = SyncFailure(error)
            rateLimit = await client.rateLimit
        }
    }

    private func watchRuns(includeRecent: Bool) async {
        guard hasToken, !isRefreshing else { return }
        var watched = Set(runsByRepo.filter { $0.value.contains(where: \.state.isActive) }.keys)
        if includeRecent {
            let dayAgo = Date().addingTimeInterval(-86_400)
            watched.formUnion(runsByRepo.filter { ($0.value.first?.createdAt ?? .distantPast) > dayAgo }.keys)
        }
        guard !watched.isEmpty else { return }
        let updates = await withTaskGroup(of: (String, [WorkflowRun]?).self) { group in
            for repo in watched {
                group.addTask { [client] in (repo, try? await client.runs(of: repo)) }
            }
            var result: [String: [WorkflowRun]] = [:]
            for await (repo, runs) in group { if let runs { result[repo] = runs } }
            return result
        }
        let merged = runsByRepo.merging(updates) { _, new in new }
        if merged != runsByRepo {
            runsByRepo = merged
            pendingDeployments = await fetchPendingDeployments()
        }
    }

    /// Asks which environments each waiting run needs approved; only runs paused on a review cost a request.
    private func fetchPendingDeployments() async -> [Int: [PendingDeployment]] {
        let waiting = runsByRepo.values.joined().filter(\.isAwaitingApproval)
        guard !waiting.isEmpty else { return [:] }
        return await withTaskGroup(of: (Int, [PendingDeployment]?).self) { group in
            for run in waiting {
                group.addTask { [client] in (run.id, try? await client.pendingDeployments(run)) }
            }
            var result: [Int: [PendingDeployment]] = [:]
            for await (id, environments) in group { if let environments { result[id] = environments } }
            return result
        }
    }

    private func refreshPulls() async {
        guard hasToken, !isRefreshing, let fresh = try? await fetchPulls() else { return }
        allPulls = fresh.filter { !isExcluded($0.repo) }
        hiddenPulls.formIntersection(allPulls.map(\.id))
        publishBadge()
    }

    /// Done and snooze marks for items that no longer exist, or snoozes that have run out, are dropped.
    private func forgetHandledItems() {
        let input = NeedsYou.Input(login: login, notifications: inbox, pulls: pulls, runsByRepo: runsByRepo,
                                   defaultBranches: defaultBranches, pendingDeployments: pendingDeployments)
        let items = NeedsYou.build(input)
        let revisions = Set(items.map(\.revision))
        if !doneItems.isSubset(of: revisions) { doneItems.formIntersection(revisions) }
        let now = Date()
        let live = snoozedItems.filter { $0.value > now }
        if live.count != snoozedItems.count { snoozedItems = live }
        hiddenItems.formIntersection(revisions)
    }

    /// Notifies about runs that appeared since the last update and are queued or running.
    private func announceStartedRuns(before old: [String: [WorkflowRun]]) {
        // An empty `old` is the first load (or a new sign-in): those runs aren't news.
        guard !old.isEmpty, defaults.bool(forKey: "notifyStartedRuns") else { return }
        let known = Set(old.values.joined().map(\.id))
        let started = runsByRepo.values.joined().filter { !known.contains($0.id) && $0.state.isActive }
        for run in started {
            post(id: "started-\(run.id)", title: "\(run.workflowName) started", subtitle: run.repo,
                 body: "\(run.displayTitle) · \(run.branchName) · \(run.event)", url: run.htmlUrl)
        }
    }

    /// Notifies about runs that were queued or running and have now completed.
    private func announceFinishedRuns(before old: [String: [WorkflowRun]]) {
        let wasActive = Set(old.values.joined().filter(\.state.isActive).map(\.id))
        guard !wasActive.isEmpty else { return }
        let finished = runsByRepo.values.joined().filter { wasActive.contains($0.id) && !$0.state.isActive }
        for run in finished {
            // The failure alert below would repeat this one; mark it as already reported.
            if run.state == .failure { knownFailures?.insert(run.id) }
            guard defaults.bool(forKey: "notifyFinishedRuns") else { continue }
            let verb = switch run.state {
            case .success: "succeeded"
            case .failure: "failed"
            case .cancelled: "was cancelled"
            default: "finished"
            }
            post(id: "finished-\(run.id)", title: "\(run.workflowName) \(verb)", subtitle: run.repo,
                 body: "\(run.displayTitle) · \(run.branchName) · \(Duration.seconds(run.duration).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow)))",
                 url: run.htmlUrl)
        }
    }

    private func refreshInbox() async {
        guard hasToken, !isRefreshing else { return }
        do {
            apply(try await client.notifications())
            failure = nil
        } catch {
            failure = SyncFailure(error)
        }
        rateLimit = await client.rateLimit
        pollInterval = await client.pollInterval
    }

    /// Runs per repository, and each repository's default branch.
    private func fetchRuns() async throws -> ([String: [WorkflowRun]], [String: String]) {
        let days = max(1, defaults.integer(forKey: "lookbackDays"))
        let repos = try await client.repos(pushedSince: Date().addingTimeInterval(-Double(days) * 86_400))
            .filter { !isExcluded($0.fullName) }  // excluded repositories cost no requests
        let branches = Dictionary(repos.compactMap { repo in repo.defaultBranch.map { (repo.fullName, $0) } },
                                  uniquingKeysWith: { first, _ in first })
        var result: [String: [WorkflowRun]] = [:]
        // ponytail: fixed batches of 8 concurrent requests; use a sliding window if hundreds of repos make this slow
        for start in stride(from: 0, to: repos.count, by: 8) {
            await withTaskGroup(of: (String, [WorkflowRun]).self) { group in
                for repo in repos[start..<min(start + 8, repos.count)] {
                    // Per-repo failures (Actions disabled, no access…) just mean "no runs".
                    group.addTask { [client] in (repo.fullName, (try? await client.runs(of: repo.fullName)) ?? []) }
                }
                for await (name, runs) in group where !runs.isEmpty { result[name] = runs }
            }
        }
        return (result, branches)
    }

    /// One search per role, merged so a PR you authored and were mentioned on appears once with both roles,
    /// plus readiness from GraphQL (without it, the queue just lacks the "can merge" and "needs changes" tiers).
    private func fetchPulls() async throws -> [PullItem] {
        async let signals = try? client.pullSignals()
        let items = try await withThrowingTaskGroup(of: (PRRole, [PullRequest]).self) { group in
            for role in PRRole.allCases {
                group.addTask { [client] in (role, try await client.searchPullRequests(role.qualifier)) }
            }
            var byID: [Int: PullItem] = [:]
            for try await (role, prs) in group {
                for pr in prs { byID[pr.id, default: PullItem(pr: pr, roles: [])].roles.insert(role) }
            }
            return Array(byID.values)
        }
        let (statuses, direct) = await signals ?? ([:], [])
        return items.map { item in
            var item = item
            let key = subjectKey(item.repo, item.number)
            item.status = statuses[key] ?? item.status
            item.isDirectReview = direct.contains(key)
            return item
        }
    }

    // MARK: - Opening links

    /// Opens items in the browser. Opening something also reads its inbox notification, or marks it seen.
    func open(_ urls: [URL]) {
        urls.forEach { NSWorkspace.shared.open($0) }
        markRead(notifications.filter { $0.unread && urls.contains($0.webURL) })
        markSeen(runsByRepo.values.joined().filter { urls.contains($0.htmlUrl) }.map(\.seenKey)
                 + pulls.filter { urls.contains($0.pr.htmlUrl) }.map(\.seenKey))
    }

    func markSeen(_ keys: [String]) {
        guard !seen.isSuperset(of: keys) else { return }
        seen.formUnion(keys)
        publishBadge()
    }

    func copyLinks(_ urls: [URL]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urls.map(\.absoluteString).joined(separator: "\n"), forType: .string)
    }

    // MARK: - Actions (G4: optimistic, undoable, written to GitHub after the undo window)

    /// Hides `item` and its threads right away; after the undo window runs `commit`, marks the threads done
    /// and refreshes with `reload`. If GitHub refuses, the item comes back marked as failed.
    private func act(on item: NeedsYouItem?, _ message: String, commit: @escaping () async throws -> Void,
                     reload: (() async -> Void)? = nil) {
        let threads = Set(item?.notificationIDs ?? [])
        actions.perform(message, apply: { [self] in
            if let item {
                hiddenItems.insert(item.revision)
                failedItems.remove(item.id)
            }
            hiddenThreads.formUnion(threads)
            publishBadge()
        }, revert: { [self] in
            if let item { hiddenItems.remove(item.revision) }
            hiddenThreads.subtract(threads)
            publishBadge()
        }, commit: { [client] in
            try await commit()
            for thread in threads { try await client.markDone(thread: thread) }
        }, completed: { [self] in
            inbox.removeAll { threads.contains($0.id) }
            hiddenThreads.subtract(threads)
            await reload?()
        }, failed: { [self] in
            if let item { failedItems.insert(item.id) }
        })
    }

    /// "api-gateway #214".
    private func label(_ repo: String, _ number: Int) -> String {
        "\(repo.split(separator: "/").last.map(String.init) ?? repo) #\(number)"
    }

    /// Done (E): the item leaves the queue until something new happens on it, and its threads are marked done.
    func done(_ item: NeedsYouItem) {
        actions.perform("Marked done", apply: { [self] in
            doneItems.insert(item.revision)
            hiddenThreads.formUnion(item.notificationIDs)
            publishBadge()
        }, revert: { [self] in
            doneItems.remove(item.revision)
            hiddenThreads.subtract(item.notificationIDs)
            publishBadge()
        }, commit: { [client] in
            for thread in item.notificationIDs { try await client.markDone(thread: thread) }
        }, completed: { [self] in
            inbox.removeAll { item.notificationIDs.contains($0.id) }
        })
    }

    /// Snooze (S): the item leaves the queue until `date`. Local only.
    func snooze(_ item: NeedsYouItem, until date: Date) {
        actions.perform("Snoozed until \(date.formatted(date: .abbreviated, time: .shortened))", apply: { [self] in
            snoozedItems[item.id] = date
            publishBadge()
        }, revert: { [self] in
            snoozedItems[item.id] = nil
            publishBadge()
        }, commit: {})
    }

    /// Submits a review. With `draftKey`, the review bar's draft clears at once and returns if GitHub refuses.
    func review(_ pull: PullItem, _ event: GitHubClient.ReviewEvent, body: String? = nil, item: NeedsYouItem? = nil,
                draftKey: String? = nil) {
        let verb = switch event {
        case .approve: "Approved"
        case .requestChanges: "Requested changes on"
        case .comment: "Commented on"
        }
        let draft = draftKey.flatMap { drafts[$0] }
        actions.perform("\(verb) \(label(pull.repo, pull.number))", apply: { [self] in
            if let item { hiddenItems.insert(item.revision) }
            if let draftKey { drafts[draftKey] = nil }
            publishBadge()
        }, revert: { [self] in
            if let item { hiddenItems.remove(item.revision) }
            if let draftKey { drafts[draftKey] = draft }
            publishBadge()
        }, commit: { [client] in
            try await client.submitReview(pull.pr.ref, event: event, body: body)
            for thread in item?.notificationIDs ?? [] { try await client.markDone(thread: thread) }
        }, completed: { [self] in
            timelineVersion += 1
            await refreshPulls()
        }, failed: { [self] in
            if let item { failedItems.insert(item.id) }
        })
    }

    /// Update branch (P5): merges the base branch into a pull request that's behind.
    func updateBranch(_ pull: PullItem) {
        act(on: nil, "Updating \(label(pull.repo, pull.number)) with its base",
            commit: { [client] in try await client.updateBranch(pull.pr.ref) },
            reload: { [self] in timelineVersion += 1; await refreshPulls() })
    }

    /// Auto-merge (P6): merges by itself once checks and reviews allow.
    func setAutoMerge(_ enabled: Bool, pull: PullItem, pullID: String, method: String) {
        act(on: nil, enabled ? "Auto-merge on for \(label(pull.repo, pull.number))" : "Auto-merge off for \(label(pull.repo, pull.number))",
            commit: { [client] in try await client.setAutoMerge(enabled, pullID: pullID, method: method) },
            reload: { [self] in timelineVersion += 1 })
    }

    /// Re-runs one failed check's job (P8).
    func rerunJob(_ id: Int, name: String, repo: String) {
        act(on: nil, "Re-running \(name)",
            commit: { [client] in try await client.rerunJob(id, repo: repo) },
            reload: { [self] in timelineVersion += 1; await reloadRuns() })
    }

    func merge(_ pull: PullItem, method: String = "squash", deleteBranch: Bool, item: NeedsYouItem? = nil) {
        let id = pull.id
        actions.perform("Merged \(label(pull.repo, pull.number))", apply: { [self] in
            if let item { hiddenItems.insert(item.revision) }
            hiddenPulls.insert(id)
            publishBadge()
        }, revert: { [self] in
            if let item { hiddenItems.remove(item.revision) }
            hiddenPulls.remove(id)
            publishBadge()
        }, commit: { [client] in
            try await client.merge(pull.pr.ref, method: method, deleteBranch: deleteBranch)
        }, completed: { [self] in
            await refreshPulls()
        }, failed: { [self] in
            if let item { failedItems.insert(item.id) }
        })
    }

    /// Approves (or rejects) every environment of the run you may review.
    func reviewDeployment(_ item: NeedsYouItem, approve: Bool, comment: String = "") {
        guard case .deployment(let run, let environments) = item.kind else { return }
        act(on: item, "\(approve ? "Approved" : "Rejected") \(run.workflowName) #\(run.runNumber)",
            commit: { [client] in
                try await client.reviewDeployments(run, environments: environments.map(\.environment.id), approve: approve, comment: comment)
            },
            reload: { [self] in await reloadRuns() })
    }

    func reply(to ref: IssueRef, body: String, item: NeedsYouItem? = nil) {
        act(on: item, "Replied on \(label(ref.repo, ref.number))",
            commit: { [client] in try await client.addComment(ref, body: body) })
    }

    func rerunFailedJobs(_ runs: [WorkflowRun], item: NeedsYouItem? = nil) {
        let runs = runs.filter(\.state.canRerunFailedJobs)
        guard !runs.isEmpty else { return }
        act(on: item, runs.count == 1 ? "Re-running failed jobs of \(runs[0].workflowName)" : "Re-running \(runs.count) runs",
            commit: { [client] in for run in runs { try await client.rerunFailedJobs(run) } },
            reload: { [self] in await reloadRuns() })
    }

    func rerunAllJobs(_ runs: [WorkflowRun], item: NeedsYouItem? = nil) {
        let runs = runs.filter { !$0.state.isActive }
        guard !runs.isEmpty else { return }
        act(on: item, runs.count == 1 ? "Re-running \(runs[0].workflowName)" : "Re-running \(runs.count) runs",
            commit: { [client] in for run in runs { try await client.rerun(run) } },
            reload: { [self] in await reloadRuns() })
    }

    /// Cancelling can't be undone on GitHub, so it goes through a confirmation dialog first.
    func requestCancel(_ runs: [WorkflowRun]) {
        pendingCancel = runs.filter(\.state.isActive)
    }

    func confirmCancel() {
        let runs = pendingCancel
        pendingCancel = []
        guard !runs.isEmpty else { return }
        act(on: nil, runs.count == 1 ? "Cancelling \(runs[0].workflowName)" : "Cancelling \(runs.count) runs",
            commit: { [client] in for run in runs { try await client.cancel(run) } },
            reload: { [self] in await reloadRuns() })
    }

    /// After a run action GitHub needs a moment to flip the status.
    private func reloadRuns() async {
        try? await Task.sleep(for: .seconds(2))
        await watchRuns(includeRecent: true)
    }

    // MARK: - Inbox actions

    /// Reading is immediate (no undo): it's what opening a thread does.
    func markRead(_ items: [GitHubNotification]) {
        let ids = Set(items.filter(\.unread).map(\.id))
        guard !ids.isEmpty else { return }
        for index in inbox.indices where ids.contains(inbox[index].id) {
            inbox[index].unread = false
        }
        // A snoozed thread that came back is handled once it's read.
        for id in ids where (snoozedThreads[id] ?? .distantFuture) <= Date() { snoozedThreads[id] = nil }
        publishBadge()
        Task {
            do {
                for item in items where ids.contains(item.id) { try await client.markRead(item) }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// Mark All Read (I1): everything in `items`, undoable. With no filter beyond a repository scope this is one
    /// PUT for the whole inbox (or repository); otherwise each thread is marked on its own.
    func markAllRead(_ items: [GitHubNotification], wholeInbox: Bool) {
        let ids = Set(items.filter(\.unread).map(\.id))
        guard !ids.isEmpty else { return }
        let repo = scopeRepo
        actions.perform(ids.count == 1 ? "Marked 1 read" : "Marked \(ids.count) read", apply: { [self] in
            readThreads.formUnion(ids)
            publishBadge()
        }, revert: { [self] in
            readThreads.subtract(ids)
            publishBadge()
        }, commit: { [client] in
            if wholeInbox {
                try await client.markAllRead(repo: repo)
            } else {
                for id in ids { try await client.markRead(thread: id) }
            }
        }, completed: { [self] in
            for index in inbox.indices where ids.contains(inbox[index].id) { inbox[index].unread = false }
            readThreads.subtract(ids)
        })
    }

    /// Snooze (I4): the thread leaves the Inbox and Now until `date`, then comes back unread at the top.
    func snooze(_ items: [GitHubNotification], until date: Date) {
        let ids = items.map(\.id)
        guard !ids.isEmpty else { return }
        let previous = ids.map { snoozedThreads[$0] }
        actions.perform("Snoozed until \(date.formatted(date: .abbreviated, time: .shortened))", apply: { [self] in
            for id in ids { snoozedThreads[id] = date }
            publishBadge()
        }, revert: { [self] in
            for (id, old) in zip(ids, previous) { snoozedThreads[id] = old }
            publishBadge()
        }, commit: {})
    }

    /// Mute (I4, I6): unsubscribes so new activity stays out of the Inbox, and marks the thread done.
    func mute(_ items: [GitHubNotification]) {
        let ids = Set(items.map(\.id))
        guard !ids.isEmpty else { return }
        actions.perform(ids.count == 1 ? "Muted thread" : "Muted \(ids.count) threads", apply: { [self] in
            hiddenThreads.formUnion(ids)
            publishBadge()
        }, revert: { [self] in
            hiddenThreads.subtract(ids)
            publishBadge()
        }, commit: { [client] in
            for id in ids {
                try await client.unsubscribe(thread: id)
                try await client.markDone(thread: id)
            }
        }, completed: { [self] in
            inbox.removeAll { ids.contains($0.id) }
            hiddenThreads.subtract(ids)
        })
    }

    /// Comment (I9), optionally closing the issue. The draft clears at once and comes back if GitHub refuses.
    /// The thread is then marked done unless Settings turns that off.
    func comment(on ref: IssueRef, body: String, close: Bool = false, thread: GitHubNotification?) {
        let key = thread?.id ?? subjectKey(ref.repo, ref.number)
        let markDone = thread != nil && defaults.bool(forKey: "doneAfterReply")
        let ids: Set<String> = markDone ? [thread!.id] : []
        actions.perform(close ? "Commented and closed \(label(ref.repo, ref.number))" : "Commented on \(label(ref.repo, ref.number))",
                        apply: { [self] in
            drafts[key] = nil
            hiddenThreads.formUnion(ids)
        }, revert: { [self] in
            drafts[key] = body
            hiddenThreads.subtract(ids)
        }, commit: { [client] in
            try await client.addComment(ref, body: body)
            if close { try await client.closeIssue(ref) }
            for id in ids { try await client.markDone(thread: id) }
        }, completed: { [self] in
            inbox.removeAll { ids.contains($0.id) }
            hiddenThreads.subtract(ids)
            timelineVersion += 1
        })
    }

    /// Done removes the thread from the inbox until something new happens on it.
    func markDone(_ items: [GitHubNotification]) {
        let ids = Set(items.map(\.id))
        guard !ids.isEmpty else { return }
        actions.perform(ids.count == 1 ? "Marked done" : "Marked \(ids.count) done", apply: { [self] in
            hiddenThreads.formUnion(ids)
            publishBadge()
        }, revert: { [self] in
            hiddenThreads.subtract(ids)
            publishBadge()
        }, commit: { [client] in
            for id in ids { try await client.markDone(thread: id) }
        }, completed: { [self] in
            inbox.removeAll { ids.contains($0.id) }
            hiddenThreads.subtract(ids)
        })
    }

    // MARK: - Account

    func signIn(token: String) {
        Keychain.save(token)
        hasToken = true
        login = nil
        start()
    }

    func signOut() {
        Keychain.delete()
        loops.forEach { $0.cancel() }
        Task { await client.resetCache() }
        hasToken = false
        login = nil
        tokenScopes = nil
        error = nil
        failure = nil
        scopeRepo = nil
        runsByRepo = [:]
        inbox = []
        allPulls = []
        hiddenPulls = []
        pendingDeployments = [:]
        hiddenItems = []
        hiddenThreads = []
        failedItems = []
        seen = []
        knownFailures = nil
        knownUnread = nil
        publishBadge()
    }

    // MARK: - Alerts

    /// The Dock badge counts the Needs-you queue (or unread plus failing; see `Config.dockBadge`).
    private func publishBadge() {
        let count = switch Config.dockBadge {
        case .needsYou: allNeedsYou.count
        case .unreadPlusFailing: unreadCount + failingCount
        }
        NSApp?.dockTile.badgeLabel = count == 0 ? nil : "\(count)"
    }

    private func apply(_ allInbox: [GitHubNotification]) {
        let fresh = allInbox.filter { !isExcluded($0.repo) }
        inbox = fresh
        publishBadge()

        let unread = fresh.filter(\.unread)
        defer { knownUnread = Set(unread.map(\.id)) }
        guard let known = knownUnread, defaults.bool(forKey: "notifyInbox") else { return }
        // Threads you started (reason "author") stay in the Inbox but don't pop up unless opted in.
        let includeOwn = defaults.bool(forKey: "notifyOwnActivity")
        for item in unread where !known.contains(item.id) && (includeOwn || item.reason != "author") {
            post(id: "inbox-\(item.id)", title: item.title, subtitle: "\(item.repo) · \(item.reasonLabel)", body: nil, url: item.webURL)
        }
    }

    private func publishFailures() {
        publishBadge()
        let failing = latestRuns.filter { $0.state == .failure }
        defer { knownFailures = Set(failing.map(\.id)) }
        guard let known = knownFailures, defaults.bool(forKey: "notifyFailures") else { return }
        for run in failing where !known.contains(run.id) {
            post(id: "run-\(run.id)", title: "\(run.workflowName) failed", subtitle: run.repo,
                 body: "\(run.displayTitle) · \(run.branchName)", url: run.htmlUrl)
        }
    }

    private func post(id: String, title: String, subtitle: String, body: String?, url: URL) {
        guard canNotify, !alertsPaused else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        if let body { content.body = body }
        content.sound = .default
        content.userInfo = ["url": url.absoluteString]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}

// MARK: - Sync status

/// Why a sync failed, as far as the status indicator cares.
enum SyncFailure: Equatable {
    case offline, unauthorized, rateLimited, other

    init(_ error: Error) {
        if let error = error as? URLError,
           [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
            .dnsLookupFailed, .timedOut, .dataNotAllowed].contains(error.code) {
            self = .offline
        } else if let error = error as? GitHubError, let status = error.status {
            if status == 401 {
                self = .unauthorized
            } else if [403, 429].contains(status), error.message.localizedCaseInsensitiveContains("rate limit") {
                self = .rateLimited
            } else {
                self = .other
            }
        } else {
            self = .other
        }
    }
}

/// The five states shown at the bottom of the sidebar (N3), most serious first.
enum SyncStatus: Equatable {
    case signInAgain, offline, rateLimited(until: Date?), syncing, live

    init(hasToken: Bool, isRefreshing: Bool, failure: SyncFailure?, rateLimit: RateLimit?, now: Date = Date()) {
        let exhausted = rateLimit.map { $0.remaining == 0 && ($0.reset ?? .distantFuture) > now } ?? false
        if !hasToken || failure == .unauthorized {
            self = .signInAgain
        } else if failure == .offline {
            self = .offline
        } else if failure == .rateLimited || exhausted {
            self = .rateLimited(until: rateLimit?.reset)
        } else if isRefreshing {
            self = .syncing
        } else {
            self = .live
        }
    }

    var title: String {
        switch self {
        case .signInAgain: "Sign in again"
        case .offline: "Offline"
        case .rateLimited: "Rate limited"
        case .syncing: "Syncing"
        case .live: "Live"
        }
    }

    var tone: Tone {
        switch self {
        case .signInAgain: .red
        case .offline: .neutral
        case .rateLimited, .syncing: .amber
        case .live: .green
        }
    }
}

// MARK: - Sync cadence

enum SyncCadence {
    /// `base`, stretched to GitHub's X-Poll-Interval, and to 2 minutes when under 5% of the quota is left.
    static func delay(_ base: Duration, rateLimit: RateLimit?, pollInterval: Int? = nil) -> Duration {
        var delay = base
        if let pollInterval { delay = max(delay, .seconds(pollInterval)) }
        if let limit = rateLimit, Double(limit.remaining) < Double(limit.limit) * 0.05 { delay = max(delay, .seconds(120)) }
        return delay
    }
}

/// What a page should select when asked by another page.
enum SelectionRequest: Equatable {
    case pull(Int), run(Int), thread(String)
}

extension Date {
    /// "now", "12m", "3h", "2d".
    func shortAge(now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(self))
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86_400: return "\(Int(seconds / 3600))h"
        default: return "\(Int(seconds / 86_400))d"
        }
    }
}

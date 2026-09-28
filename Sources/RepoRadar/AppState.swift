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

    private(set) var notifications: [GitHubNotification] = []
    private(set) var pulls: [PullItem] = []

    // MARK: Account & status

    private(set) var isRefreshing = false
    private(set) var lastUpdated: Date?
    private(set) var login: String?
    private(set) var rateLimit: RateLimit?
    private(set) var hasToken = Keychain.load() != nil
    var error: String?
    /// Set by the menu bar extra to jump the main window to a section.
    var requestedSection: SidebarItem?

    @ObservationIgnored private var loops: [Task<Void, Never>] = []
    /// Ids seen at the last refresh; nil until the first load so launching doesn't notify about old items.
    @ObservationIgnored private var knownFailures: Set<Int>?
    @ObservationIgnored private var knownUnread: Set<String>?

    private let defaults = UserDefaults.standard
    private let client = GitHubClient.shared
    private var canNotify: Bool { Bundle.main.bundleIdentifier != nil }  // `swift run` has no bundle

    init() {
        defaults.register(defaults: ["refreshMinutes": 5, "lookbackDays": 30, "notifyFailures": true, "notifyInbox": true, "notifyOwnActivity": false,
                                      "notifyFinishedRuns": true, "notifyStartedRuns": true])
    }

    var repos: [String] { runsByRepo.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } }
    var failingCount: Int { latestRuns.count(where: { $0.state == .failure }) }
    var unreadCount: Int { notifications.count(where: \.unread) }
    var reviewRequestCount: Int { pulls.count(where: { $0.roles.contains(.reviewRequested) }) }

    // MARK: - Refreshing

    func start() {
        if canNotify {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
        loops.forEach { $0.cancel() }
        loops = [
            Task {
                while !Task.isCancelled {
                    await refresh()
                    let minutes = max(1, defaults.integer(forKey: "refreshMinutes"))
                    try? await Task.sleep(for: .seconds(minutes * 60))
                }
            },
            // Runs are watched every 15 s: repos with a run in progress each time, and repos with a run
            // in the last day every minute, to catch newly started runs. Unchanged responses are free 304s.
            Task {
                var tick = 0
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(15))
                    tick += 1
                    await watchRuns(includeRecent: tick % 4 == 0)
                }
            },
            // The inbox is polled every minute: unchanged responses are 304s, which are free.
            Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    await refreshInbox()
                }
            }
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
            let (newRuns, newInbox, newPulls) = try await (runs, inbox, prs)
            runsByRepo = newRuns
            pulls = newPulls
            apply(newInbox)
            lastUpdated = Date()
            rateLimit = await client.rateLimit
            error = nil
            publishFailures()
        } catch {
            self.error = error.localizedDescription
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
        if merged != runsByRepo { runsByRepo = merged }
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
        guard hasToken, !isRefreshing, let inbox = try? await client.notifications() else { return }
        apply(inbox)
    }

    private func fetchRuns() async throws -> [String: [WorkflowRun]] {
        let days = max(1, defaults.integer(forKey: "lookbackDays"))
        let repos = try await client.repos(pushedSince: Date().addingTimeInterval(-Double(days) * 86_400))
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
        return result
    }

    /// One search per role, merged so a PR you authored and were mentioned on appears once with both roles.
    private func fetchPulls() async throws -> [PullItem] {
        try await withThrowingTaskGroup(of: (PRRole, [PullRequest]).self) { group in
            for role in PRRole.allCases {
                group.addTask { [client] in (role, try await client.searchPullRequests(role.qualifier)) }
            }
            var byID: [Int: PullItem] = [:]
            for try await (role, prs) in group {
                for pr in prs { byID[pr.id, default: PullItem(pr: pr, roles: [])].roles.insert(role) }
            }
            return Array(byID.values)
        }
    }

    // MARK: - Opening links

    /// Opens items in the browser. Opening something also reads its inbox notification.
    func open(_ urls: [URL]) {
        urls.forEach { NSWorkspace.shared.open($0) }
        markRead(notifications.filter { $0.unread && urls.contains($0.webURL) })
    }

    func copyLinks(_ urls: [URL]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urls.map(\.absoluteString).joined(separator: "\n"), forType: .string)
    }

    // MARK: - Run actions

    func rerunFailedJobs(_ runs: [WorkflowRun]) {
        perform(runs.filter(\.state.canRerunFailedJobs)) { [client] in try await client.rerunFailedJobs($0) }
    }

    func rerunAllJobs(_ runs: [WorkflowRun]) {
        perform(runs.filter { !$0.state.isActive }) { [client] in try await client.rerun($0) }
    }

    /// Cancelling can't be undone, so it goes through a confirmation dialog first.
    func requestCancel(_ runs: [WorkflowRun]) {
        pendingCancel = runs.filter(\.state.isActive)
    }

    func confirmCancel() {
        perform(pendingCancel) { [client] in try await client.cancel($0) }
        pendingCancel = []
    }

    private func perform(_ runs: [WorkflowRun], _ action: @escaping (WorkflowRun) async throws -> Void) {
        guard !runs.isEmpty else { return }
        Task {
            do {
                for run in runs { try await action(run) }
                try? await Task.sleep(for: .seconds(2))  // give GitHub a moment to flip the status
                await refresh()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    // MARK: - Inbox actions (optimistic: update locally, then tell GitHub)

    func markRead(_ items: [GitHubNotification]) {
        let ids = Set(items.filter(\.unread).map(\.id))
        guard !ids.isEmpty else { return }
        for index in notifications.indices where ids.contains(notifications[index].id) {
            notifications[index].unread = false
        }
        publishBadge()
        Task {
            do {
                for item in items where ids.contains(item.id) { try await client.markRead(item) }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// Done removes the thread from the inbox until something new happens on it.
    func markDone(_ items: [GitHubNotification]) {
        let ids = Set(items.map(\.id))
        guard !ids.isEmpty else { return }
        notifications.removeAll { ids.contains($0.id) }
        publishBadge()
        Task {
            do {
                for item in items { try await client.markDone(item) }
            } catch {
                self.error = error.localizedDescription
            }
        }
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
        error = nil
        runsByRepo = [:]
        notifications = []
        pulls = []
        knownFailures = nil
        knownUnread = nil
        publishBadge()
    }

    // MARK: - Alerts

    /// Dock badge counts what needs attention: unread notifications plus failing workflows.
    private func publishBadge() {
        let count = unreadCount + failingCount
        NSApp.dockTile.badgeLabel = count == 0 ? nil : "\(count)"
    }

    private func apply(_ inbox: [GitHubNotification]) {
        notifications = inbox
        publishBadge()

        let unread = inbox.filter(\.unread)
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
        guard canNotify else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        if let body { content.body = body }
        content.sound = .default
        content.userInfo = ["url": url.absoluteString]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}

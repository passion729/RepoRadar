import Foundation
import SwiftUI
import UserNotifications

enum FontSettings {
    static let minSize = 10
    static let maxSize = 28
    static let defaultUISize = 14
    static let defaultMonoSize = 14
    static let defaultMenuSize = 12
}

/// Central observable store for the whole app.
@MainActor
final class AppState: ObservableObject {
    @Published var repositories: [Repository] = []
    @Published var pullRequestsByRepo: [String: [PullRequest]] = [:]
    @Published var myPullRequests: [RelatedPullRequest] = []
    @Published var isLoadingMyPRs = false
    @Published var notifications: [GitHubNotification] = []
    /// Authenticated user's login, for building github.com quick links.
    @Published var userLogin: String?

    var myGitHubURL: URL {
        URL(string: userLogin.map { "https://github.com/\($0)" } ?? "https://github.com")!
    }
    var allPullsURL: URL { URL(string: "https://github.com/pulls")! }
    var githubNotificationsURL: URL { URL(string: "https://github.com/notifications")! }
    var myReposURL: URL {
        URL(string: userLogin.map { "https://github.com/\($0)?tab=repositories" } ?? "https://github.com")!
    }

    /// Per-repo detail PRs (all open + last-month closed), keyed by "owner/name".
    /// Keying by repo means a late-finishing fetch can never land under the
    /// wrong repo, and cached repos don't re-fetch on every sidebar switch.
    @Published var repoDetailPRs: [String: [PullRequest]] = [:]
    @Published var loadingRepoDetail: Set<String> = []
    private var repoDetailFetchedAt: [String: Date] = [:]
    private let repoDetailStaleSeconds: TimeInterval = 60

    /// Closed/merged PRs are limited to the last `recentDays`; open PRs are unbounded.
    static let recentDays = 30
    @Published var token: String = ""
    @Published var lastError: String?
    @Published var isRefreshing = false
    @Published var deviceCode: DeviceCodePrompt?
    @Published var lastRefreshed: Date?

    /// Auto-refresh interval in minutes (minimum 1). Persisted; changing it
    /// reschedules the timer without forcing an immediate refresh.
    @Published var refreshIntervalMinutes: Int {
        didSet {
            UserDefaults.standard.set(refreshIntervalMinutes, forKey: Self.refreshIntervalKey)
            startAutoRefresh(immediate: false)
        }
    }
    static let minRefreshMinutes = 1
    private static let refreshIntervalKey = "reporadar.refreshIntervalMinutes"

    /// App-wide font settings (persisted). The resolved `fontTheme` is injected
    /// into the SwiftUI environment at every scene root, so the main window and
    /// the menu bar stay in sync.
    /// Empty string = system font. Otherwise an installed font family name.
    @Published var uiFontFamily: String {
        didSet { UserDefaults.standard.set(uiFontFamily, forKey: Self.uiFontFamilyKey) }
    }
    @Published var monoFontFamily: String {
        didSet { UserDefaults.standard.set(monoFontFamily, forKey: Self.monoFontFamilyKey) }
    }
    @Published var uiFontSize: Int {
        didSet { UserDefaults.standard.set(uiFontSize, forKey: Self.uiFontSizeKey) }
    }
    @Published var monoFontSize: Int {
        didSet { UserDefaults.standard.set(monoFontSize, forKey: Self.monoFontSizeKey) }
    }
    /// Menu-bar popover gets its own UI font + size (the window is compact, so a
    /// smaller, distinct font usually reads better). Mono is shared with the main UI.
    @Published var menuFontFamily: String {
        didSet { UserDefaults.standard.set(menuFontFamily, forKey: Self.menuFontFamilyKey) }
    }
    @Published var menuFontSize: Int {
        didSet { UserDefaults.standard.set(menuFontSize, forKey: Self.menuFontSizeKey) }
    }
    private static let uiFontFamilyKey = "reporadar.uiFontFamily"
    private static let monoFontFamilyKey = "reporadar.monoFontFamily"
    private static let uiFontSizeKey = "reporadar.uiFontSize"
    private static let monoFontSizeKey = "reporadar.monoFontSize"
    private static let menuFontFamilyKey = "reporadar.menuFontFamily"
    private static let menuFontSizeKey = "reporadar.menuFontSize"

    /// Theme for the main window & settings.
    var fontTheme: FontTheme {
        FontTheme(
            uiFamily: uiFontFamily,
            uiBodySize: CGFloat(uiFontSize),
            monoFamily: monoFontFamily,
            monoBodySize: CGFloat(monoFontSize)
        )
    }

    /// Theme for the menu-bar popover (its own UI font/size; shared mono).
    var menuFontTheme: FontTheme {
        FontTheme(
            uiFamily: menuFontFamily,
            uiBodySize: CGFloat(menuFontSize),
            monoFamily: monoFontFamily,
            monoBodySize: CGFloat(monoFontSize)
        )
    }

    /// Shown in the UI while the user authorizes a device-flow login.
    struct DeviceCodePrompt: Equatable {
        let userCode: String
        let verificationURI: String
    }

    private let repoDefaultsKey = "reporadar.repositories"
    private var refreshTask: Task<Void, Never>?
    private var notificationsTask: Task<Void, Never>?
    private var deviceFlowTask: Task<Void, Never>?
    private var seenNotificationIDs: Set<String> = []
    private var didInitialNotificationSync = false

    var totalOpenPRs: Int {
        pullRequestsByRepo.values.reduce(0) { $0 + $1.count }
    }
    var totalMyPRs: Int {
        myPullRequests.count
    }
    /// Open PRs only — used for the actionable sidebar/menu badge.
    var openMyPRsCount: Int {
        myPullRequests.filter { $0.pr.prState == .open }.count
    }
    var unreadNotifications: Int {
        notifications.filter(\.unread).count
    }

    /// Related PRs of a given status, newest-first (the loaded subset).
    func myPullRequests(in state: PRState) -> [RelatedPullRequest] {
        myPullRequests
            .filter { $0.pr.prState == state }
            .sorted { $0.pr.updatedAt > $1.pr.updatedAt }
    }
    func myPRsCount(in state: PRState) -> Int {
        myPullRequests.reduce(0) { $0 + ($1.pr.prState == state ? 1 : 0) }
    }

    /// All notifications grouped by repository, each sorted newest-first.
    var notificationsByRepo: [(repo: String, items: [GitHubNotification])] {
        Dictionary(grouping: notifications) { $0.repository.fullName }
            .map { (repo: $0.key, items: $0.value.sorted { $0.updatedAt > $1.updatedAt }) }
            .sorted { $0.repo.localizedCaseInsensitiveCompare($1.repo) == .orderedAscending }
    }

    init() {
        let stored = UserDefaults.standard.integer(forKey: Self.refreshIntervalKey)
        refreshIntervalMinutes = stored >= Self.minRefreshMinutes ? stored : 5
        let storedUIFamily = UserDefaults.standard.string(forKey: Self.uiFontFamilyKey) ?? ""
        uiFontFamily = FontCatalog.isInstalledUIFamily(storedUIFamily) ? storedUIFamily : ""
        let storedMonoFamily = UserDefaults.standard.string(forKey: Self.monoFontFamilyKey) ?? ""
        monoFontFamily = FontCatalog.isInstalledMonoFamily(storedMonoFamily) ? storedMonoFamily : ""
        let storedUISize = UserDefaults.standard.integer(forKey: Self.uiFontSizeKey)
        uiFontSize = storedUISize >= FontSettings.minSize ? storedUISize : FontSettings.defaultUISize
        let storedMonoSize = UserDefaults.standard.integer(forKey: Self.monoFontSizeKey)
        monoFontSize = storedMonoSize >= FontSettings.minSize ? storedMonoSize : FontSettings.defaultMonoSize
        let storedMenuFamily = UserDefaults.standard.string(forKey: Self.menuFontFamilyKey) ?? ""
        menuFontFamily = FontCatalog.isInstalledUIFamily(storedMenuFamily) ? storedMenuFamily : ""
        let storedMenuSize = UserDefaults.standard.integer(forKey: Self.menuFontSizeKey)
        menuFontSize = storedMenuSize >= FontSettings.minSize ? storedMenuSize : FontSettings.defaultMenuSize
        loadRepositories()
        token = KeychainStore.loadToken() ?? ""
    }

    // MARK: - Lifecycle

    func bootstrap() {
        requestNotificationPermission()
        startAutoRefresh()
        startNotificationsPolling()
    }

    // MARK: - Token

    func saveToken(_ newToken: String) {
        let trimmed = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        token = trimmed
        if trimmed.isEmpty {
            KeychainStore.deleteToken()
        } else {
            KeychainStore.saveToken(trimmed)
        }
    }

    /// Starts GitHub's OAuth device flow: fetch a user code, surface it for the
    /// UI to display, then poll in the background until authorized. The resulting
    /// access token is stored in the Keychain via `saveToken`, like a pasted PAT.
    func startDeviceFlow() async {
        lastError = nil
        do {
            let response = try await GitHubDeviceFlow.shared.requestDeviceCode()
            deviceCode = DeviceCodePrompt(
                userCode: response.user_code,
                verificationURI: response.verification_uri
            )
            deviceFlowTask?.cancel()
            deviceFlowTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let token = try await GitHubDeviceFlow.shared.poll(
                        deviceCode: response.device_code,
                        interval: response.interval,
                        expiresIn: response.expires_in
                    )
                    self.deviceCode = nil
                    self.saveToken(token)
                    await self.refresh()
                } catch is CancellationError {
                    // User cancelled — nothing to report.
                } catch {
                    self.deviceCode = nil
                    self.lastError = self.describe(error)
                }
            }
        } catch {
            lastError = describe(error)
        }
    }

    func cancelDeviceFlow() {
        deviceFlowTask?.cancel()
        deviceFlowTask = nil
        deviceCode = nil
    }

    func signOut() {
        cancelDeviceFlow()
        saveToken("")
        pullRequestsByRepo = [:]
        notifications = []
        userLogin = nil
    }

    // MARK: - Repositories

    @discardableResult
    func addRepository(_ raw: String) async -> Bool {
        guard let repo = Repository(fullName: raw) else {
            lastError = Localizer.t(.cannotParseRepo(raw))
            return false
        }
        guard !repositories.contains(repo) else {
            lastError = Localizer.t(.repoAlreadyAdded(repo.fullName))
            return false
        }
        do {
            try await GitHubClient.shared.verify(repo: repo)
            repositories.append(repo)
            persistRepositories()
            await refresh()
            return true
        } catch {
            lastError = describe(error)
            return false
        }
    }

    func removeRepository(_ repo: Repository) {
        repositories.removeAll { $0 == repo }
        pullRequestsByRepo[repo.fullName] = nil
        repoDetailPRs[repo.fullName] = nil
        persistRepositories()
    }

    private func loadRepositories() {
        guard
            let data = UserDefaults.standard.data(forKey: repoDefaultsKey),
            let repos = try? JSONDecoder().decode([Repository].self, from: data)
        else { return }
        repositories = repos
    }

    private func persistRepositories() {
        if let data = try? JSONEncoder().encode(repositories) {
            UserDefaults.standard.set(data, forKey: repoDefaultsKey)
        }
    }

    // MARK: - Refresh

    func refresh() async {
        guard !token.isEmpty else {
            lastError = Localizer.t(.noTokenShort)
            return
        }
        guard !isRefreshing else { return }   // ignore re-entrant refreshes
        isRefreshing = true
        defer { isRefreshing = false }
        lastError = nil

        if userLogin == nil {
            userLogin = try? await GitHubClient.shared.currentUserLogin()
        }

        // Pull requests for each monitored repo, concurrently. A nil result
        // means unchanged (304) or a transient error — keep the existing data.
        await withTaskGroup(of: (String, [PullRequest]?).self) { group in
            for repo in repositories {
                group.addTask {
                    let prs = (try? await GitHubClient.shared.pullRequests(for: repo)) ?? nil
                    return (repo.fullName, prs)
                }
            }
            for await (fullName, prs) in group {
                if let prs { pullRequestsByRepo[fullName] = prs }
            }
        }

        // PRs related to me (authored / assigned / review / mentioned).
        await loadRelatedPRs()

        // Notifications run on their own faster loop, but refresh them here too
        // so a manual refresh updates everything at once.
        await pollNotifications()

        lastRefreshed = Date()
    }

    // MARK: - Related PRs (all open + last-month closed/merged)

    private static let myPRsBatch = 20   // items per page wave

    /// Loads related PRs in time-ordered batches: newest first, one page at a
    /// time across all relationships, appending each wave to the list. Open PRs
    /// stream in first, then closed/merged from the last month.
    func loadRelatedPRs() async {
        guard !token.isEmpty else { return }
        isLoadingMyPRs = true
        defer { isLoadingMyPRs = false }

        let since = Self.dateString(daysAgo: Self.recentDays)
        var byID: [Int: RelatedPullRequest] = [:]

        func runPhase(state: String) async {
            var active = Set(PRRelation.allCases)   // relationships with more pages
            var page = 1
            while !active.isEmpty && page <= 10 {
                let rels = Array(active)
                let waves = await withTaskGroup(of: (PRRelation, [PullRequest])?.self) { group -> [(PRRelation, [PullRequest])] in
                    for rel in rels {
                        group.addTask {
                            guard let prs = try? await GitHubClient.shared.searchPRsPage(
                                qualifier: rel.searchQualifier,
                                state: state,
                                page: page,
                                perPage: Self.myPRsBatch
                            ) else { return nil }
                            return (rel, prs)
                        }
                    }
                    var out: [(PRRelation, [PullRequest])] = []
                    for await result in group { if let result { out.append(result) } }
                    return out
                }
                for (rel, prs) in waves {
                    for pr in prs {
                        byID[pr.id, default: RelatedPullRequest(pr: pr, relations: [])]
                            .relations.insert(rel)
                    }
                    if prs.count < Self.myPRsBatch { active.remove(rel) }   // exhausted
                }
                myPullRequests = Array(byID.values)   // append this wave
                page += 1
            }
        }

        await runPhase(state: "is:open")
        await runPhase(state: "is:closed updated:>=\(since)")
    }

    /// Loads a repo's detail PRs into the cache. Skips if already loading or if
    /// the cache is still fresh (unless `force`). Result is stored under the
    /// repo key, so switching repos mid-flight never crosses data over.
    func loadRepoDetail(_ repo: Repository, force: Bool = false) async {
        guard !token.isEmpty else { return }
        let key = repo.fullName
        if loadingRepoDetail.contains(key) { return }
        if !force,
           let at = repoDetailFetchedAt[key],
           Date().timeIntervalSince(at) < repoDetailStaleSeconds {
            return
        }
        loadingRepoDetail.insert(key)
        defer { loadingRepoDetail.remove(key) }
        let since = Calendar.current.date(byAdding: .day, value: -Self.recentDays, to: Date()) ?? Date()
        do {
            // Show open PRs first, then fill in closed/merged.
            let open = try await GitHubClient.shared.openRepoPRs(repo)
            repoDetailPRs[key] = open
            let closed = (try? await GitHubClient.shared.recentClosedRepoPRs(repo, since: since)) ?? []
            repoDetailPRs[key] = open + closed
            repoDetailFetchedAt[key] = Date()
        } catch {
            // Keep any previously cached data on error.
        }
    }

    static func dateString(daysAgo: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - Notifications polling

    /// Dedicated near-real-time notifications loop. Uses conditional requests
    /// (cheap 304s) and obeys GitHub's `X-Poll-Interval` (~60s), independent of
    /// the PR refresh interval.
    func startNotificationsPolling() {
        notificationsTask?.cancel()
        notificationsTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollNotifications()
                let seconds = await GitHubClient.shared.notificationsPollSeconds()
                try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            }
        }
    }

    /// Fetches notifications conditionally; a nil result means "unchanged".
    func pollNotifications() async {
        guard !token.isEmpty else { return }
        do {
            guard let fetched = try await GitHubClient.shared.notifications() else { return }
            deliverSystemNotifications(for: fetched)
            notifications = fetched.sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            // Transient; the next tick will retry.
        }
    }

    /// (Re)starts the auto-refresh timer using `refreshIntervalMinutes`.
    /// Pass `immediate: false` to reschedule without an instant refresh
    /// (e.g. when the user is just adjusting the interval).
    func startAutoRefresh(immediate: Bool = true) {
        refreshTask?.cancel()
        let nanos = UInt64(max(Self.minRefreshMinutes, refreshIntervalMinutes) * 60) * 1_000_000_000
        refreshTask = Task { [weak self] in
            if immediate { await self?.refresh() }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: nanos)
                guard !Task.isCancelled else { break }
                await self?.refresh()
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        notificationsTask?.cancel()
        notificationsTask = nil
    }

    // MARK: - System notifications

    func requestNotificationPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func deliverSystemNotifications(for items: [GitHubNotification]) {
        let unread = items.filter(\.unread)

        // On the very first sync just remember what's already there,
        // so we don't fire a banner for every pre-existing notification.
        guard didInitialNotificationSync else {
            seenNotificationIDs = Set(unread.map(\.id))
            didInitialNotificationSync = true
            return
        }

        let center = UNUserNotificationCenter.current()
        for item in unread where !seenNotificationIDs.contains(item.id) {
            seenNotificationIDs.insert(item.id)
            let content = UNMutableNotificationContent()
            content.title = item.repository.fullName
            content.subtitle = friendlyReason(item.reason)
            content.body = item.subject.title
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: item.id,
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }

    private func friendlyReason(_ reason: String) -> String {
        switch reason {
        case "review_requested": return Localizer.t(.reasonReviewRequested)
        case "mention": return Localizer.t(.reasonMention)
        case "assign": return Localizer.t(.reasonAssign)
        case "author": return Localizer.t(.reasonAuthor)
        case "comment": return Localizer.t(.reasonComment)
        case "state_change": return Localizer.t(.reasonStateChange)
        default: return reason
        }
    }

    // MARK: - Helpers

    private func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

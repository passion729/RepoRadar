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
    @Published var notifications: [GitHubNotification] = []
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

    /// PRs related to me, grouped by status (Open → Merged → Closed),
    /// each sorted newest-first.
    var myPullRequestsByStatus: [(state: PRState, prs: [RelatedPullRequest])] {
        Dictionary(grouping: myPullRequests) { $0.pr.prState }
            .map { (state: $0.key, prs: $0.value.sorted { $0.pr.updatedAt > $1.pr.updatedAt }) }
            .sorted { $0.state.sortIndex < $1.state.sortIndex }
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

        // Pull requests for each monitored repo, concurrently.
        await withTaskGroup(of: (String, [PullRequest]?).self) { group in
            for repo in repositories {
                group.addTask {
                    let prs = try? await GitHubClient.shared.pullRequests(for: repo)
                    return (repo.fullName, prs)
                }
            }
            for await (fullName, prs) in group {
                if let prs { pullRequestsByRepo[fullName] = prs }
            }
        }

        // Open PRs related to me (authored / assigned / review / mentioned).
        do {
            myPullRequests = try await GitHubClient.shared.relatedOpenPullRequests()
        } catch {
            lastError = describe(error)
        }

        // All account notifications (not limited to monitored repos).
        do {
            let fetched = try await GitHubClient.shared.notifications()
            deliverSystemNotifications(for: fetched)
            notifications = fetched.sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            lastError = describe(error)
        }

        lastRefreshed = Date()
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

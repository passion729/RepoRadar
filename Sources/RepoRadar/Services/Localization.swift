import Foundation
import Combine

/// Languages offered in Settings. Default is English (US).
/// Raw values match the `.lproj` directory names under Resources.
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case chinese = "zh-Hans"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English (US)"
        case .chinese: return "简体中文"
        }
    }
}

/// In-app localization built on Foundation's native `.lproj`/`Localizable.strings`
/// infrastructure, but with **live switching** independent of the system language:
/// strings are looked up against the chosen language's bundle directly, so the UI
/// updates instantly without an app restart.
///
/// Views observe `language` via `@EnvironmentObject` and call `loc(.someKey)`;
/// non-view code (errors, services) uses the static `Localizer.t(_:)`.
final class Localizer: ObservableObject {
    static let shared = Localizer()
    static let defaultsKey = "reporadar.language"

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.defaultsKey) }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.defaultsKey)
        language = AppLanguage(rawValue: raw ?? "") ?? .english
    }

    /// `loc(.someKey)` in views — establishes a SwiftUI dependency on `language`.
    func callAsFunction(_ key: LocKey) -> String {
        Self.localized(key, language: language)
    }

    /// Lookup usable anywhere (reads the persisted language directly).
    static func t(_ key: LocKey) -> String {
        let raw = UserDefaults.standard.string(forKey: defaultsKey)
        let language = AppLanguage(rawValue: raw ?? "") ?? .english
        return localized(key, language: language)
    }

    // MARK: - Native bundle lookup

    private static var bundleCache: [AppLanguage: Bundle] = [:]

    /// The SwiftPM-generated resource bundle, located robustly across layouts:
    /// the packaged app's `Contents/Resources`, the `.app` root (where SwiftPM's
    /// own `Bundle.module` looks), and the executable's directory (dev / swift run).
    private static let resourceBundle: Bundle = {
        let name = "RepoRadar_RepoRadar.bundle"
        let searchURLs = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            Bundle.main.executableURL?.deletingLastPathComponent()
        ].compactMap { $0 }

        for base in searchURLs {
            if let bundle = Bundle(url: base.appendingPathComponent(name)) {
                return bundle
            }
        }
        return .module // dev fallback (hardcoded .build path)
    }()

    private static func bundle(for language: AppLanguage) -> Bundle {
        if let cached = bundleCache[language] { return cached }
        // SwiftPM may emit the .lproj name lower-cased (e.g. zh-hans.lproj),
        // so try the canonical tag and its lowercase form.
        let candidates = [language.rawValue, language.rawValue.lowercased()]
        let path = candidates.lazy
            .compactMap { resourceBundle.path(forResource: $0, ofType: "lproj") }
            .first
        let resolved = path.flatMap(Bundle.init(path:)) ?? resourceBundle
        bundleCache[language] = resolved
        return resolved
    }

    private static func localized(_ key: LocKey, language: AppLanguage) -> String {
        let format = bundle(for: language)
            .localizedString(forKey: key.key, value: key.key, table: nil)
        guard !key.arguments.isEmpty else { return format }
        return String(format: format, arguments: key.arguments)
    }
}

/// Type-safe handle to a localized string. `key` matches an entry in the
/// `Localizable.strings` files; parameterized cases carry their format arguments.
enum LocKey {
    // Common actions
    case refresh
    case settings
    case cancel
    case save
    case saved
    case add
    case remove

    // Main window — toolbar & sidebar
    case addRepoHelp
    case openRepoInBrowser
    case sectionOverview
    case sectionRepositories
    case notifications
    case relatedPRsSidebar
    case noReposSidebar
    case needLogin
    case openSettings
    case lastRefreshed(String)

    // Related PRs view
    case relatedPRsTitle(Int)
    case relatedPRsEmptyTitle
    case relatedPRsEmptyDesc

    // Notifications view
    case notificationsTitle(Int)
    case notificationsEmptyTitle
    case notificationsEmptyDesc
    case unreadCount(Int)

    // Per-repo PR list
    case prListEmptyTitle

    // PR status groups
    case prStatusOpen
    case prStatusMerged
    case prStatusClosed

    // PR relationship badges
    case relationAuthored
    case relationAssigned
    case relationReviewRequested
    case relationMentioned

    // Add repository sheet
    case addRepoTitle
    case addRepoSubtitle
    case addRepoPlaceholder

    // Settings
    case loginSectionTitle
    case loggedIn
    case signOut
    case signInWithGitHub
    case deviceFlowHint
    case enterDeviceCode
    case copyAndOpenGitHub
    case waitingForAuth
    case patSectionTitle
    case patHint
    case createToken
    case refreshSectionHint
    case refreshIntervalLabel(Int)
    case languageSectionTitle
    case interfaceLanguage
    case fontSectionTitle
    case uiFontFamilyLabel
    case monoFontFamilyLabel
    case systemFont
    case systemMonoFont
    case uiFontSizeLabel(Int)
    case monoFontSizeLabel(Int)
    case menuFontSectionTitle
    case menuFontFamilyLabel
    case menuFontSizeLabel(Int)

    // Menu bar
    case menuNotLoggedIn
    case menuLoginHint
    case pillRelatedPRs
    case pillRepoPRs
    case pillUnread
    case sectionRelatedPRs
    case sectionRecentNotifications
    case noReposMenuHint
    case noOpenPRs
    case openMainWindow
    case quit

    // AppState errors / reasons
    case cannotParseRepo(String)
    case repoAlreadyAdded(String)
    case noTokenShort
    case reasonReviewRequested
    case reasonMention
    case reasonAssign
    case reasonAuthor
    case reasonComment
    case reasonStateChange

    // GitHub client errors
    case ghNotAuthenticated
    case ghHTTP(Int, String)
    case ghDecoding(String)

    // OAuth errors
    case oauthCancelled
    case oauthExpired
    case oauthHTTP(Int)
    case oauthServer(String)

    // Internal fallbacks
    case unknownResponse
    case noHTTPResponse
    case otherGroup

    /// The `.strings` lookup key.
    var key: String {
        switch self {
        case .refresh: return "action.refresh"
        case .settings: return "action.settings"
        case .cancel: return "action.cancel"
        case .save: return "action.save"
        case .saved: return "action.saved"
        case .add: return "action.add"
        case .remove: return "action.remove"

        case .addRepoHelp: return "toolbar.addRepo"
        case .openRepoInBrowser: return "toolbar.openRepoInBrowser"
        case .sectionOverview: return "sidebar.overview"
        case .sectionRepositories: return "sidebar.repositories"
        case .notifications: return "sidebar.notifications"
        case .relatedPRsSidebar: return "sidebar.relatedPRs"
        case .noReposSidebar: return "sidebar.noRepos"
        case .needLogin: return "detail.needLogin"
        case .openSettings: return "detail.openSettings"
        case .lastRefreshed: return "sidebar.lastRefreshed"

        case .relatedPRsTitle: return "relatedPRs.title"
        case .relatedPRsEmptyTitle: return "relatedPRs.emptyTitle"
        case .relatedPRsEmptyDesc: return "relatedPRs.emptyDesc"

        case .notificationsTitle: return "notifications.title"
        case .notificationsEmptyTitle: return "notifications.emptyTitle"
        case .notificationsEmptyDesc: return "notifications.emptyDesc"
        case .unreadCount: return "notifications.unreadCount"

        case .prListEmptyTitle: return "prList.emptyTitle"

        case .prStatusOpen: return "prStatus.open"
        case .prStatusMerged: return "prStatus.merged"
        case .prStatusClosed: return "prStatus.closed"

        case .relationAuthored: return "relation.authored"
        case .relationAssigned: return "relation.assigned"
        case .relationReviewRequested: return "relation.reviewRequested"
        case .relationMentioned: return "relation.mentioned"

        case .addRepoTitle: return "addRepo.title"
        case .addRepoSubtitle: return "addRepo.subtitle"
        case .addRepoPlaceholder: return "addRepo.placeholder"

        case .loginSectionTitle: return "settings.loginSection"
        case .loggedIn: return "settings.loggedIn"
        case .signOut: return "settings.signOut"
        case .signInWithGitHub: return "settings.signIn"
        case .deviceFlowHint: return "settings.deviceFlowHint"
        case .enterDeviceCode: return "settings.enterDeviceCode"
        case .copyAndOpenGitHub: return "settings.copyAndOpen"
        case .waitingForAuth: return "settings.waitingForAuth"
        case .patSectionTitle: return "settings.patSection"
        case .patHint: return "settings.patHint"
        case .createToken: return "settings.createToken"
        case .refreshSectionHint: return "settings.refreshHint"
        case .refreshIntervalLabel: return "settings.refreshInterval"
        case .languageSectionTitle: return "settings.languageSection"
        case .interfaceLanguage: return "settings.interfaceLanguage"
        case .fontSectionTitle: return "settings.fontSection"
        case .uiFontFamilyLabel: return "settings.uiFontFamily"
        case .monoFontFamilyLabel: return "settings.monoFontFamily"
        case .systemFont: return "settings.systemFont"
        case .systemMonoFont: return "settings.systemMonoFont"
        case .uiFontSizeLabel: return "settings.uiFontSize"
        case .monoFontSizeLabel: return "settings.monoFontSize"
        case .menuFontSectionTitle: return "settings.menuFontSection"
        case .menuFontFamilyLabel: return "settings.menuFontFamily"
        case .menuFontSizeLabel: return "settings.menuFontSize"

        case .menuNotLoggedIn: return "menu.notLoggedIn"
        case .menuLoginHint: return "menu.loginHint"
        case .pillRelatedPRs: return "menu.pill.relatedPRs"
        case .pillRepoPRs: return "menu.pill.repoPRs"
        case .pillUnread: return "menu.pill.unread"
        case .sectionRelatedPRs: return "menu.section.relatedPRs"
        case .sectionRecentNotifications: return "menu.section.recentNotifications"
        case .noReposMenuHint: return "menu.noReposHint"
        case .noOpenPRs: return "menu.noOpenPRs"
        case .openMainWindow: return "menu.openMainWindow"
        case .quit: return "menu.quit"

        case .cannotParseRepo: return "error.cannotParseRepo"
        case .repoAlreadyAdded: return "error.repoAlreadyAdded"
        case .noTokenShort: return "error.noTokenShort"
        case .reasonReviewRequested: return "reason.reviewRequested"
        case .reasonMention: return "reason.mention"
        case .reasonAssign: return "reason.assign"
        case .reasonAuthor: return "reason.author"
        case .reasonComment: return "reason.comment"
        case .reasonStateChange: return "reason.stateChange"

        case .ghNotAuthenticated: return "error.gh.notAuthenticated"
        case .ghHTTP: return "error.gh.http"
        case .ghDecoding: return "error.gh.decoding"

        case .oauthCancelled: return "error.oauth.cancelled"
        case .oauthExpired: return "error.oauth.expired"
        case .oauthHTTP: return "error.oauth.http"
        case .oauthServer: return "error.oauth.server"

        case .unknownResponse: return "fallback.unknownResponse"
        case .noHTTPResponse: return "fallback.noHTTPResponse"
        case .otherGroup: return "fallback.otherGroup"
        }
    }

    /// Format arguments for parameterized strings (order matches the format).
    var arguments: [CVarArg] {
        switch self {
        case .lastRefreshed(let value): return [value]
        case .refreshIntervalLabel(let count): return [count]
        case .uiFontSizeLabel(let size): return [size]
        case .monoFontSizeLabel(let size): return [size]
        case .menuFontSizeLabel(let size): return [size]
        case .relatedPRsTitle(let count): return [count]
        case .notificationsTitle(let count): return [count]
        case .unreadCount(let count): return [count]
        case .cannotParseRepo(let value): return [value]
        case .repoAlreadyAdded(let value): return [value]
        case .ghHTTP(let code, let message): return [code, message]
        case .ghDecoding(let message): return [message]
        case .oauthHTTP(let code): return [code]
        case .oauthServer(let message): return [message]
        default: return []
        }
    }
}

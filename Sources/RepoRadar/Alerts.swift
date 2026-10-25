import Foundation
import UserNotifications

/// System alerts (G6): only your push failing on the default branch, a new review request, an @-mention and
/// a deployment waiting for you. Everything else updates counts silently.
enum Alerts {
    enum Kind: CaseIterable {
        case pushFailed, review, mention, deployment

        init?(_ item: NeedsYouItem) {
            switch item.kind {
            case .pushFailed: self = .pushFailed
            case .review: self = .review
            case .mention: self = .mention
            case .deployment: self = .deployment
            case .mergeable, .changesRequested: return nil
            }
        }

        /// The Settings switch for this kind.
        var setting: String {
            switch self {
            case .pushFailed: "notifyPushFailed"
            case .review: "notifyReviews"
            case .mention: "notifyMentions"
            case .deployment: "notifyDeployments"
            }
        }

        var title: String {
            switch self {
            case .pushFailed: "Your push fails on the default branch"
            case .review: "Someone requests your review"
            case .mention: "Someone mentions you"
            case .deployment: "A deployment waits for your approval"
            }
        }

        /// The notification category, which decides the buttons.
        var category: String {
            switch self {
            case .pushFailed: "PUSH_FAILED"
            case .deployment: "DEPLOYMENT"
            case .review, .mention: Alerts.openCategory
            }
        }
    }

    static let openCategory = "OPEN"
    static let rerunAction = "RERUN"
    static let approveAction = "APPROVE"
    static let openAction = "OPEN"

    /// Re-run failed · Approve · Open buttons on the alerts.
    static var categories: Set<UNNotificationCategory> {
        let open = UNNotificationAction(identifier: openAction, title: "Open", options: [.foreground])
        let rerun = UNNotificationAction(identifier: rerunAction, title: "Re-run failed", options: [])
        let approve = UNNotificationAction(identifier: approveAction, title: "Approve", options: [.authenticationRequired])
        return [
            UNNotificationCategory(identifier: Kind.pushFailed.category, actions: [rerun, open], intentIdentifiers: []),
            UNNotificationCategory(identifier: Kind.deployment.category, actions: [approve, open], intentIdentifiers: []),
            UNNotificationCategory(identifier: openCategory, actions: [open], intentIdentifiers: []),
        ]
    }

    /// Items to alert about: new since last time (by revision), of a kind that alerts and is switched on.
    static func fresh(_ items: [NeedsYouItem], known: Set<String>, enabled: [Kind]) -> [NeedsYouItem] {
        items.filter { item in
            guard !known.contains(item.revision), let kind = Kind(item) else { return false }
            return enabled.contains(kind)
        }
    }

    static func content(for item: NeedsYouItem) -> (kind: Kind, title: String, subtitle: String, body: String) {
        let kind = Kind(item)!
        switch item.kind {
        case .pushFailed(let run):
            return (kind, "\(run.workflowName) failed on \(run.branchName)", run.repo,
                    "\(run.displayTitle) · run #\(run.runNumber)")
        case .deployment(let run, let environments):
            let names = environments.compactMap(\.environment.name).joined(separator: ", ")
            return (kind, "\(run.workflowName) is waiting for your approval", run.repo,
                    names.isEmpty ? run.displayTitle : "Deploy to \(names) · \(run.displayTitle)")
        case .review(let pull, _, _):
            return (kind, "Review requested: \(pull.title)", "\(pull.repo) #\(pull.number)", "by \(pull.author)")
        case .mention(let note):
            return (kind, "You were mentioned", note.repo + (note.ref.map { " #\($0.number)" } ?? ""), note.title)
        case .mergeable, .changesRequested:
            return (kind, item.title, item.repo, "")
        }
    }
}

import Foundation

/// Open product decisions (redesign spec §10), at their default values. Change them here.
enum Config {
    /// How long an inline action waits before it's sent to GitHub, and how long its toast offers Undo.
    /// Merging and approving deployments wait too.
    static let undoWindow: Duration = .seconds(4)

    /// How often runs in progress are refreshed; with none running, runs are checked every minute.
    static let activeRunRefresh: Duration = .seconds(15)

    enum DockBadge { case needsYou, unreadPlusFailing }
    /// What the Dock badge counts.
    static let dockBadge = DockBadge.needsYou

    /// Accounts whose review requests drop a tier in Needs you, and whose notifications group together.
    static let botLogins: Set<String> = ["dependabot[bot]", "renovate[bot]", "github-actions[bot]"]

    /// github.com only: GitHub Enterprise Server and several accounts aren't supported yet.
    static let apiHost = "https://api.github.com"
}

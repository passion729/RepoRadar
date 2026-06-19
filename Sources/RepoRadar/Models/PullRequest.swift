import Foundation

/// Subset of the GitHub "pull request" object returned by
/// GET /repos/{owner}/{repo}/pulls
struct PullRequest: Identifiable, Codable, Hashable {
    let id: Int
    let number: Int
    let title: String
    let state: String          // "open" | "closed"
    let htmlURL: URL
    let user: Author
    let createdAt: Date
    let updatedAt: Date
    let draft: Bool?
    /// Top-level merge timestamp from the repo pulls API (nil if unmerged).
    let mergedAt: Date?
    /// Present on search-API results; carries merge info to distinguish
    /// merged from plain-closed PRs.
    let pullRequest: PullRequestMeta?

    struct PullRequestMeta: Codable, Hashable {
        let mergedAt: Date?
        enum CodingKeys: String, CodingKey {
            case mergedAt = "merged_at"
        }
    }

    struct Author: Codable, Hashable {
        let login: String
        let avatarURL: URL?

        enum CodingKeys: String, CodingKey {
            case login
            case avatarURL = "avatar_url"
        }
    }

    var isDraft: Bool { draft ?? false }

    /// Coarse PR status used for grouping. A merged PR reports `state == "closed"`
    /// with a non-nil `merged_at`, so we check that to separate it from a plain close.
    var prState: PRState {
        if state == "open" { return .open }
        let isMerged = mergedAt != nil || pullRequest?.mergedAt != nil
        return isMerged ? .merged : .closed
    }

    /// "owner/name" parsed from the html_url (…/owner/name/pull/123).
    /// Works for both the per-repo pulls API and the cross-repo search API,
    /// since neither response carries a `full_name` on the PR object itself.
    var repoFullName: String? {
        let parts = htmlURL.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { return nil }
        return "\(parts[0])/\(parts[1])"
    }

    enum CodingKeys: String, CodingKey {
        case id, number, title, state, user, draft
        case htmlURL = "html_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case mergedAt = "merged_at"
        case pullRequest = "pull_request"
    }
}

/// Coarse pull-request status for grouping.
enum PRState: String {
    case open, merged, closed

    var sortIndex: Int {
        switch self {
        case .open: return 0
        case .merged: return 1
        case .closed: return 2
        }
    }

    var labelKey: LocKey {
        switch self {
        case .open: return .prStatusOpen
        case .merged: return .prStatusMerged
        case .closed: return .prStatusClosed
        }
    }

    /// GitHub octicon path for this state (rendered via OcticonShape).
    var octiconPath: String {
        switch self {
        case .open: return OcticonPath.gitPullRequest
        case .merged: return OcticonPath.gitMerge
        case .closed: return OcticonPath.gitPullRequestClosed
        }
    }
}

/// How an open PR relates to the logged-in user. Mirrors the tabs on GitHub's
/// own https://github.com/pulls page.
enum PRRelation: String, CaseIterable, Hashable {
    case authored
    case assigned
    case reviewRequested
    case mentioned

    /// GitHub search qualifier that selects this relationship.
    var searchQualifier: String {
        switch self {
        case .authored: return "author:@me"
        case .assigned: return "assignee:@me"
        case .reviewRequested: return "review-requested:@me"
        case .mentioned: return "mentions:@me"
        }
    }

    var labelKey: LocKey {
        switch self {
        case .authored: return .relationAuthored
        case .assigned: return .relationAssigned
        case .reviewRequested: return .relationReviewRequested
        case .mentioned: return .relationMentioned
        }
    }

    var systemImage: String {
        switch self {
        case .authored: return "pencil"
        case .assigned: return "person"
        case .reviewRequested: return "eye"
        case .mentioned: return "at"
        }
    }

    /// Stable display order for badges.
    var sortIndex: Int {
        switch self {
        case .authored: return 0
        case .assigned: return 1
        case .reviewRequested: return 2
        case .mentioned: return 3
        }
    }
}

/// A PR plus every way it relates to the logged-in user (a PR can match more
/// than one relationship — e.g. authored *and* mentioned).
struct RelatedPullRequest: Identifiable, Hashable {
    let pr: PullRequest
    var relations: Set<PRRelation>

    var id: Int { pr.id }
    var sortedRelations: [PRRelation] {
        relations.sorted { $0.sortIndex < $1.sortIndex }
    }
}

import SwiftUI

struct PullRequestRow: View {
    let pr: PullRequest
    /// How this PR relates to the current user; empty in plain per-repo lists.
    var relations: Set<PRRelation> = []
    /// Show the owning repo in the subtitle (used in the cross-repo aggregate).
    var showRepo: Bool = false
    @EnvironmentObject var loc: Localizer
    @Environment(\.fontTheme) private var theme
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(pr.htmlURL)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(pr.title)
                        .font(theme.ui(.subheadline))
                        .lineLimit(2)
                    Text(subtitle)
                        .font(theme.ui(.caption))
                        .foregroundStyle(.secondary)
                    if !relations.isEmpty {
                        relationBadges
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        let meta = "#\(pr.number) · \(pr.user.login) · \(pr.updatedAt.formatted(.relative(presentation: .named)))"
        if showRepo, let repo = pr.repoFullName {
            return "\(repo) · \(meta)"
        }
        return meta
    }

    /// Open draft PRs get the draft glyph; otherwise the icon reflects the state.
    private var statusIcon: String {
        if pr.prState == .open && pr.isDraft { return "pencil.circle" }
        return pr.prState.systemImage
    }

    private var statusColor: Color {
        switch pr.prState {
        case .open: return pr.isDraft ? .secondary : .green
        case .merged: return .purple
        case .closed: return .red
        }
    }

    private var relationBadges: some View {
        HStack(spacing: 4) {
            ForEach(relations.sorted { $0.sortIndex < $1.sortIndex }, id: \.self) { relation in
                let tint = tint(for: relation)
                HStack(spacing: 2) {
                    Image(systemName: relation.systemImage)
                    Text(loc(relation.labelKey))
                }
                .font(theme.ui(.caption2))
                .foregroundStyle(tint)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(tint.opacity(0.15), in: Capsule())
            }
        }
    }

    /// Distinct color per relationship, so the tags are scannable at a glance.
    private func tint(for relation: PRRelation) -> Color {
        switch relation {
        case .authored: return .blue
        case .assigned: return .purple
        case .reviewRequested: return .orange
        case .mentioned: return .teal
        }
    }
}

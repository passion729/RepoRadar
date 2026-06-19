import SwiftUI
import AppKit

struct MenuBarContentView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var loc: Localizer
    @Environment(\.fontTheme) private var theme
    @Environment(\.openWindow) private var openWindow

    /// Measured height of the scrollable content (drives the popover size).
    @State private var scrollContentHeight: CGFloat = 0

    /// Cap the scroll area so the whole popover stays within ~2/3 of the screen.
    /// ~96pt is reserved for the header, footer and dividers.
    private var maxScrollHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 800
        return max(200, screen * 2 / 3 - 96)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Image(systemName: "dot.radiowaves.left.and.right")
            Text("RepoRadar").font(theme.ui(.headline))
            Spacer()
            if state.isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await state.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help(loc(.refresh))
            }
        }
        .padding(10)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if state.token.isEmpty {
            placeholder(
                icon: "key",
                title: loc(.menuNotLoggedIn),
                subtitle: loc(.menuLoginHint)
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    summary

                    if !state.myPullRequests.isEmpty {
                        sectionHeader(loc(.sectionRelatedPRs))
                        ForEach(state.myPullRequests.prefix(5)) { item in
                            PullRequestRow(pr: item.pr, relations: item.relations)
                                .padding(.horizontal, 10)
                        }
                    }

                    if !state.notifications.isEmpty {
                        sectionHeader(loc(.sectionRecentNotifications))
                        ForEach(state.notifications.prefix(5)) { item in
                            NotificationRow(notification: item)
                                .padding(.horizontal, 10)
                        }
                    }

                    sectionHeader(loc(.sectionRepositories))
                    if state.repositories.isEmpty {
                        Text(loc(.noReposMenuHint))
                            .font(theme.ui(.caption))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                    } else {
                        ForEach(state.repositories) { repo in
                            repoDisclosure(repo)
                        }
                    }
                }
                .padding(.vertical, 8)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: ScrollHeightKey.self, value: geo.size.height)
                    }
                )
            }
            .frame(height: min(scrollContentHeight == 0 ? maxScrollHeight : scrollContentHeight, maxScrollHeight))
            .onPreferenceChange(ScrollHeightKey.self) { scrollContentHeight = $0 }
        }
    }

    private var summary: some View {
        HStack(spacing: 10) {
            summaryPill(count: state.openMyPRsCount, label: loc(.pillRelatedPRs), system: "arrow.triangle.pull")
            summaryPill(count: state.totalOpenPRs, label: loc(.pillRepoPRs), system: "folder")
            summaryPill(count: state.unreadNotifications, label: loc(.pillUnread), system: "bell.badge")
        }
        .padding(.horizontal, 10)
    }

    private func repoDisclosure(_ repo: Repository) -> some View {
        let prs = state.pullRequestsByRepo[repo.fullName] ?? []
        return DisclosureGroup {
            if prs.isEmpty {
                Text(loc(.noOpenPRs))
                    .font(theme.ui(.caption))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 18)
            } else {
                ForEach(prs) { pr in
                    PullRequestRow(pr: pr)
                        .padding(.leading, 18)
                }
            }
        } label: {
            HStack {
                Image(systemName: "folder")
                Text(repo.fullName).font(theme.ui(.subheadline, weight: .medium))
                Spacer()
                Text("\(prs.count)")
                    .font(theme.ui(.caption))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button(loc(.openMainWindow)) {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.borderless)
            Spacer()
            SettingsLink { Text(loc(.settings)) }
                .buttonStyle(.borderless)
            Button(loc(.quit)) {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
    }

    // MARK: Building blocks

    private func summaryPill(count: Int, label: String, system: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: system)
            Text("\(count)").font(theme.ui(.headline))
            Text(label).font(theme.ui(.caption)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(theme.ui(.caption, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
    }

    private func placeholder(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(theme.ui(.largeTitle))
                .foregroundStyle(.secondary)
            Text(title).font(theme.ui(.headline))
            Text(subtitle)
                .font(theme.ui(.caption))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding()
    }
}

/// Measures the menu bar's scrollable content height so the popover can grow
/// with its content and cap at the screen-relative maximum.
private struct ScrollHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

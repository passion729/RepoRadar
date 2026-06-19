import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var loc: Localizer
    @Environment(\.fontTheme) private var theme
    @Environment(\.openURL) private var openURL
    @State private var selection: SidebarItem? = .myPRs
    @State private var showingAdd = false

    enum SidebarItem: Hashable {
        case myPRs
        case notifications
        case repo(Repository)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 170, ideal: 220, max: 360)
        } detail: {
            detail
        }
        .sheet(isPresented: $showingAdd) {
            AddRepositoryView()
                .environmentObject(state)
        }
        .toolbar {
            ToolbarItem {
                // Native toolbar button so it matches the system sidebar-toggle
                // button's sizing. Swap only the label (icon ↔ spinner) so the
                // button itself never resizes.
                Button { Task { await state.refresh() } } label: {
                    if state.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .help(loc(.refresh))
                .disabled(state.isRefreshing)
            }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section(loc(.sectionOverview)) {
                Label {
                    HStack {
                        Text(loc(.relatedPRsSidebar))
                        Spacer()
                        if state.openMyPRsCount > 0 {
                            badge(state.openMyPRsCount)
                        }
                    }
                } icon: {
                    Image(systemName: "arrow.triangle.pull")
                }
                .tag(SidebarItem.myPRs)

                Label {
                    HStack {
                        Text(loc(.notifications))
                        Spacer()
                        if state.unreadNotifications > 0 {
                            badge(state.unreadNotifications)
                        }
                    }
                } icon: {
                    Image(systemName: "bell")
                }
                .tag(SidebarItem.notifications)
            }

            Section {
                if state.repositories.isEmpty {
                    Text(loc(.noReposSidebar))
                        .font(theme.ui(.caption))
                        .foregroundStyle(.secondary)
                }
                ForEach(state.repositories) { repo in
                    let count = state.pullRequestsByRepo[repo.fullName]?.count ?? 0
                    Label {
                        HStack {
                            Text(repo.fullName)
                            Spacer()
                            if count > 0 { badge(count) }
                        }
                    } icon: {
                        Image(systemName: "folder")
                    }
                    .tag(SidebarItem.repo(repo))
                    .contextMenu {
                        Button(loc(.openRepoInBrowser)) {
                            openURL(repo.webURL)
                        }
                        Divider()
                        Button(loc(.remove), role: .destructive) {
                            state.removeRepository(repo)
                            if selection == .repo(repo) { selection = .myPRs }
                        }
                    }
                }
            } header: {
                HStack(spacing: 0) {
                    Text(loc(.sectionRepositories))
                    Spacer()
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help(loc(.addRepoHelp))
                    .padding(.trailing, 6)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let stamp = state.lastRefreshed {
                Text(loc(.lastRefreshed(stamp.formatted(date: .omitted, time: .shortened))))
                    .font(theme.ui(.caption2))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let error = state.lastError, state.token.isEmpty {
            ContentUnavailableView {
                Label(loc(.needLogin), systemImage: "key")
            } description: {
                Text(error)
            } actions: {
                SettingsLink { Text(loc(.openSettings)) }
            }
        } else {
            switch selection {
            case .myPRs, .none:
                MyPullRequestsView()
            case .notifications:
                NotificationListView()
            case .repo(let repo):
                PullRequestListView(repo: repo)
            }
        }
    }

    private func badge(_ count: Int) -> some View {
        Text("\(count)")
            .font(theme.ui(.caption2, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
    }
}

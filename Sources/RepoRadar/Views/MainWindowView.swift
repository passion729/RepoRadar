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
            ToolbarItemGroup {
                Button { openURL(state.myGitHubURL) } label: {
                    Image(systemName: "person.crop.circle")
                }
                .help(loc(.openMyGitHub))
                Button { openURL(state.allPullsURL) } label: {
                    Image(nsImage: OcticonPath.templateImage(OcticonPath.gitPullRequest, size: 16))
                }
                .help(loc(.openAllPRs))
                Button { openURL(state.myReposURL) } label: {
                    Image(systemName: "folder")
                }
                .help(loc(.openAllRepos))
                Button { openURL(state.githubNotificationsURL) } label: {
                    Image(systemName: "bell")
                }
                .help(loc(.openGitHubNotifications))
            }

            // Refresh sits in its own item so it's spaced apart from the links.
            ToolbarItem {
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
                Text(loc(.lastRefreshed(refreshedText(stamp))))
                    .font(.caption2)   // system font, independent of the custom font setting
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

    /// Within an hour → relative ("5 minutes ago"); otherwise an absolute
    /// date + time ("Jun 19, 4:30 PM").
    private func refreshedText(_ date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 60 { return loc(.justNow) }
        if elapsed < 3600 { return date.formatted(.relative(presentation: .named)) }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func badge(_ count: Int) -> some View {
        Text("\(count)")
            .font(theme.ui(.caption2, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
    }
}

import SwiftUI

/// The four pages, organized by intent rather than by data source (spec §1).
enum Page: String, CaseIterable, Identifiable {
    case now, inbox, pulls, actions

    var id: Self { self }

    var title: String {
        switch self {
        case .now: "Now"
        case .inbox: "Inbox"
        case .pulls: "Pull Requests"
        case .actions: "Actions"
        }
    }

    var symbol: String {
        switch self {
        case .now: "waveform.path.ecg"
        case .inbox: "tray"
        case .pulls: "arrow.triangle.pull"
        case .actions: "bolt.circle"
        }
    }

    var color: Color {
        switch self {
        case .now: Theme.Nav.now
        case .inbox: Theme.Nav.inbox
        case .pulls: Theme.Nav.pulls
        case .actions: Theme.Nav.actions
        }
    }

    /// ⌘1–⌘4.
    var shortcut: KeyEquivalent {
        KeyEquivalent(Character("\(Page.allCases.firstIndex(of: self)! + 1)"))
    }
}

struct MainView: View {
    @Environment(AppState.self) private var state
    @SceneStorage("page") private var page: Page = .now
    @State private var search = ""
    @State private var isSearching = false
    @State private var jumpIndex = 0

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
            Sidebar(page: $page)
                .navigationSplitViewColumnWidth(min: 220, ideal: 248, max: 320)
        } detail: {
            content
                .navigationTitle(page.title)
                .toolbar { scopeTag }
        }
        .toasts(state.toasts)
        .onChange(of: page) { search = "" }
        .onChange(of: search) { jumpIndex = 0 }
        .onChange(of: state.requestedPage, initial: true) {
            guard let requested = state.requestedPage else { return }
            page = requested
            state.requestedPage = nil
        }
        // ⌘1–⌘4 go to the pages across all repositories, like the sidebar's top rows.
        .focusedSceneValue(\.page, Binding(get: { page }, set: {
            page = $0
            state.scopeRepo = nil
        }))
    }

    @ViewBuilder private var content: some View {
        if state.hasToken {
            Group {
                switch page {
                case .now: NowView(toolbar: standardToolbar)
                case .inbox: InboxView(search: search, toolbar: standardToolbar)
                case .pulls: PullsView(search: search, toolbar: standardToolbar)
                case .actions: ActionsView(search: search, toolbar: standardToolbar)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                if isSearching, !search.isEmpty {
                    JumpResults(results: jumpResults, selected: jumpIndex, open: open)
                        .padding(.top, 8)
                        .padding(.trailing, 12)
                }
            }
            .confirmationDialog(
                state.pendingCancel.count == 1 ? "Cancel this run?" : "Cancel \(state.pendingCancel.count) runs?",
                isPresented: Binding(get: { !state.pendingCancel.isEmpty }, set: { if !$0 { state.pendingCancel = [] } })
            ) {
                Button("Cancel Run", role: .destructive) { state.confirmCancel() }
                Button("Keep Running", role: .cancel) {}
            } message: {
                Text("GitHub stops the in-progress jobs. You can re-run them afterwards.")
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let error = state.error {
                    ErrorBanner(message: error) { state.error = nil }
                        .padding([.horizontal, .top], 8)
                }
            }
        } else {
            SignInPrompt()
                .toolbar { standardToolbar }
        }
    }

    @ToolbarContentBuilder private var scopeTag: some ToolbarContent {
        if let repo = state.scopeRepo {
            ToolbarItem(placement: .navigation) {
                ScopeTag(repo: repo) { state.scopeRepo = nil }
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    /// Search and the global buttons. Pages add it after their own items, so page actions sit to the left.
    private var standardToolbar: StandardToolbar {
        StandardToolbar(search: AnyView(
            SearchField(prompt: SearchField.toolbarPrompt, text: $search,
                        onFocusChange: { focused in
                            // Let a click on a result land before the list goes away.
                            if focused { isSearching = true } else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { isSearching = false } }
                        },
                        onKey: handleJumpKey)
                .frame(width: 280)))
    }
}

/// The toolbar every page ends with: search, Refresh · Filter · Notifications, and the account.
struct StandardToolbar: ToolbarContent {
    let search: AnyView

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) { search }
            .sharedBackgroundVisibility(.hidden)
        ToolbarItemGroup(placement: .primaryAction) {
            RefreshButton()
            RepoFilterButton()
            AlertSettingsButton()
        }
        ToolbarItem(placement: .primaryAction) { AccountButton() }
            .sharedBackgroundVisibility(.hidden)
    }
}

extension MainView {
    var jumpResults: [JumpResult] {
        Jump.results(JumpQuery(search), repos: state.repos, pulls: state.pulls, notifications: state.notifications,
                     runs: Array(state.runsByRepo.values.joined()))
    }

    /// ↑↓ pick a result, ↵ opens it in RepoRadar, ⌘↵ in the browser.
    func handleJumpKey(_ press: KeyPress) -> KeyPress.Result {
        let results = jumpResults
        guard !search.isEmpty, !results.isEmpty else { return .ignored }
        switch press.key {
        case .downArrow: jumpIndex = min(jumpIndex + 1, results.count - 1)
        case .upArrow: jumpIndex = max(jumpIndex - 1, 0)
        case .return: open(results[min(jumpIndex, results.count - 1)], inBrowser: press.modifiers.contains(.command))
        default: return .ignored
        }
        return .handled
    }

    func open(_ result: JumpResult, inBrowser: Bool) {
        search = ""
        isSearching = false
        if inBrowser {
            state.open([result.webURL])
            return
        }
        switch result.target {
        case .repo(let repo): state.scopeRepo = repo
        case .pull(let pull): state.navigate(to: .pulls, select: .pull(pull.id))
        case .issue(let note): state.navigate(to: .inbox, select: .thread(note.id))
        case .workflow(let run): state.navigate(to: .actions, select: .run(run.id))
        case .web(let url): state.open([url])
        }
    }
}

/// The toolbar's "filtered to this repository" tag (G7); clearing it shows everything again.
private struct ScopeTag: View {
    let repo: String
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            RepoSquare(repo: repo, size: 16)
            Text(repo).textStyle(.label).foregroundStyle(Theme.Ink.primary)
            Button("Show All Repositories", systemImage: "xmark", action: clear)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.Ink.secondary)
                .help("Show all repositories")
        }
        .padding(.leading, 3)
        .padding(.trailing, 9)
        .frame(height: 24)
        .background(Theme.Fill.subtle, in: .capsule)
    }
}

struct RefreshButton: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button("Refresh", systemImage: "arrow.clockwise") { Task { await state.refresh() } }
            .symbolEffect(.rotate, isActive: state.isRefreshing && !reduceMotion)
            .disabled(state.isRefreshing || !state.hasToken)
            .help("Refresh (⌘R)")
    }
}

// MARK: - Sidebar

/// The four pages across every repository, then the repositories added to the sidebar. Exactly one row is the
/// open destination: a page, or a repository with the same four pages, filtered to it, nested under it.
struct Sidebar: View {
    @Environment(AppState.self) private var state
    @Binding var page: Page

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Page.allCases) { item in
                        NavRow(page: item, isSelected: state.scopeRepo == nil && page == item, badge: badge(item, in: nil)) {
                            page = item
                            state.scopeRepo = nil
                        }
                        if item == .pulls && page == .pulls && state.scopeRepo == nil { PullListRows(indent: 38) }
                    }
                    SidebarRepos(page: $page, badge: badge)
                        .padding(.top, 16)
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)
            }
            .scrollBounceBehavior(.basedOnSize)
            SyncStatusButton(page: $page)
        }
    }

    /// Now in blue, failures in red, the rest gray; nothing at 0.
    private func badge(_ page: Page, in repo: String?) -> (count: Int, tone: Tone)? {
        let count = state.count(page, in: repo)
        let tone: Tone = switch page {
        case .now: .blue
        case .actions: .red
        case .inbox, .pulls: .neutral
        }
        return count > 0 ? (count, tone) : nil
    }
}

private struct NavRow: View {
    let page: Page
    let isSelected: Bool
    let badge: (count: Int, tone: Tone)?
    let select: () -> Void
    @Environment(\.appearsActive) private var appearsActive
    @State private var isHovered = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                Image(systemName: page.symbol)
                    .font(.system(size: 16))
                    .foregroundStyle(appearsActive ? page.color : Theme.Ink.tertiary)
                    .frame(width: 20)
                Text(page.title)
                    .textStyle(.rowTitle)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(Theme.Ink.primary)
                Spacer(minLength: 4)
                if let badge { Badge(count: badge.count, tone: badge.tone) }
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(isSelected ? Theme.Selection.nav : isHovered ? Theme.Fill.hover : .clear,
                        in: .rect(cornerRadius: Theme.Radius.nav))
            .contentShape(.rect(cornerRadius: Theme.Radius.nav))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("\(page.title) (⌘\(page.shortcut.character))")
        .accessibilityLabel(badge.map { "\(page.title), \($0.count)" } ?? page.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// An indented row under a page or repository: a pull request list, or one of a repository's pages.
private struct SubRow: View {
    let title: String
    let isSelected: Bool
    let badge: (count: Int, tone: Tone)?
    let indent: CGFloat
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack {
                Text(title)
                    .textStyle(.rowTitle)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(Theme.Ink.primary)
                Spacer()
                if let badge { Badge(count: badge.count, tone: badge.tone) }
            }
            .padding(.leading, indent)
            .padding(.trailing, 8)
            .frame(height: 28)
            .background(isSelected ? Theme.Fill.subtle : .clear, in: .rect(cornerRadius: Theme.Radius.nav))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badge.map { "\(title), \($0.count)" } ?? title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Waiting on you / Yours / Mentioned under Pull Requests while it's open (P1).
private struct PullListRows: View {
    @Environment(AppState.self) private var state
    @SceneStorage("pullList") private var list: PullList = .waiting
    let indent: CGFloat

    var body: some View {
        ForEach(PullList.allCases) { option in
            let count = state.pulls.count { state.inScope($0.repo) && option.matches($0) }
            SubRow(title: option.title, isSelected: list == option,
                   badge: count > 0 ? (count, option == .waiting ? .blue : .neutral) : nil, indent: indent) { list = option }
        }
    }
}

/// Sidebar repositories (N2): click one to open it, drag to reorder, right-click to remove; + adds more.
private struct SidebarRepos: View {
    @Environment(AppState.self) private var state
    @Binding var page: Page
    let badge: (Page, String?) -> (count: Int, tone: Tone)?
    @State private var isAdding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Repositories").textStyle(.label).foregroundStyle(Theme.Ink.tertiary)
                Spacer()
                Button("Add Repository", systemImage: "plus") { isAdding.toggle() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Ink.tertiary)
                    .help("Add a repository")
                    .popover(isPresented: $isAdding, arrowEdge: .trailing) { AddRepoPopover() }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)

            if state.sidebarRepos.isEmpty {
                Text("Add repositories with + to see each one's pull requests, runs and notifications on its own.")
                    .textStyle(.meta)
                    .foregroundStyle(Theme.Ink.tertiary)
                    .padding(.horizontal, 8)
            }
            ForEach(state.sidebarRepos, id: \.self) { repo in
                RepoRow(repo: repo, isSelected: state.scopeRepo == repo)
                if state.scopeRepo == repo {
                    ForEach(Page.allCases) { item in
                        SubRow(title: item.title, isSelected: page == item, badge: badge(item, repo), indent: 38) { page = item }
                        if item == .pulls && page == .pulls { PullListRows(indent: 54) }
                    }
                }
            }
        }
    }
}

private struct RepoRow: View {
    @Environment(AppState.self) private var state
    let repo: String
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        Button { state.scopeRepo = repo } label: {
            HStack(spacing: 8) {
                RepoSquare(repo: repo)
                Text(repo.split(separator: "/").last.map(String.init) ?? repo)
                    .textStyle(.rowTitle)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(Theme.Ink.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                RunCells(runs: state.defaultBranchRuns(of: repo), count: 6)
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(isSelected ? Theme.Selection.nav : isHovered ? Theme.Fill.hover : .clear,
                        in: .rect(cornerRadius: Theme.Radius.nav))
            .contentShape(.rect(cornerRadius: Theme.Radius.nav))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(repo)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Opens this repository")
        .draggable(repo)
        .dropDestination(for: String.self) { items, _ in
            guard let moved = items.first else { return false }
            state.moveSidebarRepo(moved, to: repo)
            return true
        }
        .contextMenu {
            Button("Remove from Sidebar", systemImage: "minus.circle") { state.removeFromSidebar(repo) }
            Button("Open on GitHub", systemImage: "safari") { state.open([URL(string: "https://github.com/\(repo)")!]) }
        }
    }
}

/// Every repository of your account, filtered as you type, plus matching repositories found on GitHub.
/// Stays open so several can be added in a row.
private struct AddRepoPopover: View {
    @Environment(AppState.self) private var state
    @State private var query = ""
    @State private var found: [String] = []

    var body: some View {
        let term = query.trimmingCharacters(in: .whitespaces)
        let mine = (state.accountRepos ?? []).filter { term.isEmpty || $0.localizedCaseInsensitiveContains(term) }
        let others = found.filter { !(state.accountRepos ?? []).contains($0) }
        VStack(alignment: .leading, spacing: 0) {
            SearchField(prompt: "Search repositories, or owner/name", text: $query, shortcut: nil)
                .padding(12)
            Rectangle().fill(Theme.separator).frame(height: 1)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    section("Your repositories", mine)
                    section("On GitHub", others)
                    if state.accountRepos == nil {
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(10)
                    } else if mine.isEmpty && others.isEmpty {
                        Text(term.count < 2 ? "No repositories yet." : "No repositories match “\(term)”.")
                            .textStyle(.meta)
                            .foregroundStyle(Theme.Ink.tertiary)
                            .padding(10)
                    }
                }
                .padding(8)
            }
            .frame(height: 420)
        }
        .frame(width: 360)
        .task { await state.loadAccountRepos() }
        .task(id: term) {
            found = []
            guard term.count >= 2 else { return }
            try? await Task.sleep(for: .milliseconds(400))  // search allows 30 requests a minute
            guard !Task.isCancelled else { return }
            found = await state.searchRepos(term)
        }
    }

    @ViewBuilder private func section(_ title: String, _ repos: [String]) -> some View {
        if !repos.isEmpty {
            Text(title)
                .textStyle(.label)
                .foregroundStyle(Theme.Ink.tertiary)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 2)
            ForEach(repos, id: \.self) { AddRepoRow(repo: $0) }
        }
    }
}

private struct AddRepoRow: View {
    @Environment(AppState.self) private var state
    let repo: String
    @State private var isHovered = false

    var body: some View {
        let added = state.sidebarRepos.contains(repo)
        Button { added ? state.removeFromSidebar(repo) : state.addToSidebar(repo) } label: {
            HStack(spacing: 8) {
                RepoSquare(repo: repo)
                Text(repo).textStyle(.rowTitle).fontWeight(.regular).foregroundStyle(Theme.Ink.primary).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(added ? Theme.accent : Theme.Ink.tertiary)
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(isHovered ? Theme.Fill.hover : .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(added ? "Remove from the sidebar" : "Add to the sidebar")
        .accessibilityAddTraits(added ? .isSelected : [])
    }
}

/// Live / Syncing / Rate limited / Offline / Sign in again, plus the API quota (N3). Opens the status popover.
private struct SyncStatusButton: View {
    @Environment(AppState.self) private var state
    @Binding var page: Page
    @State private var showDetails = false

    var body: some View {
        let status = state.syncStatus
        Button { showDetails.toggle() } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(status.tone.solid).frame(width: 7, height: 7)
                    Text(status.title).textStyle(.label).foregroundStyle(Theme.Ink.primary)
                    detail(status).textStyle(.meta).foregroundStyle(Theme.Ink.secondary).lineLimit(1)
                }
                if let limit = state.rateLimit {
                    HStack(spacing: 8) {
                        QuotaBar(limit: limit)
                        Text("\(limit.remaining.formatted()) / \(limit.limit.formatted())")
                            .textStyle(.meta)
                            .foregroundStyle(Theme.Ink.tertiary)
                            .fixedSize()
                    }
                    .help("GitHub API requests left this hour")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showDetails, arrowEdge: .top) {
            StatusPopover(page: $page)
        }
        .help("Account and sync status")
    }

    private func detail(_ status: SyncStatus) -> Text {
        switch status {
        case .rateLimited(let until?):
            Text("· until \(until.formatted(date: .omitted, time: .shortened))")
        case .signInAgain:
            Text("· open Settings")
        default:
            if let date = state.lastUpdated {
                Text("· synced \(Text(date, style: .relative)) ago")
            } else {
                Text("")
            }
        }
    }
}

private struct QuotaBar: View {
    let limit: RateLimit

    var body: some View {
        let fraction = Double(limit.remaining) / Double(max(limit.limit, 1))
        GeometryReader { proxy in
            Capsule().fill(Theme.Fill.subtle)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(fraction < 0.05 ? Tone.red.solid : fraction < 0.2 ? Tone.amber.solid : Theme.Ink.tertiary)
                        .frame(width: proxy.size.width * fraction)
                }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

struct StatusPopover: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @Binding var page: Page

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow { Text("Account").foregroundStyle(.secondary); Text(state.login.map { "@\($0)" } ?? "—") }
                GridRow { Text("Status").foregroundStyle(.secondary); Text(state.syncStatus.title) }
                GridRow {
                    Text("Last update").foregroundStyle(.secondary)
                    Text(state.lastUpdated?.formatted(date: .omitted, time: .standard) ?? "—")
                }
                GridRow {
                    Text("API quota").foregroundStyle(.secondary)
                    Text(state.rateLimit.map { "\($0.remaining) / \($0.limit) left this hour" } ?? "—")
                }
                if let reset = state.rateLimit?.reset {
                    GridRow { Text("Quota resets").foregroundStyle(.secondary); Text(reset.formatted(date: .omitted, time: .shortened)) }
                }
                GridRow { Text("Unread").foregroundStyle(.secondary); Text("\(state.unreadCount)") }
                GridRow { Text("Review requests").foregroundStyle(.secondary); Text("\(state.reviewRequestCount)") }
                GridRow { Text("Failing workflows").foregroundStyle(.secondary); Text("\(state.failingCount)") }
            }
            .monospacedDigit()
            if let error = state.error {
                Text(error).foregroundStyle(Tone.red.text).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if state.failingCount > 0 {
                    Button("Show Failing") {
                        page = .actions
                        dismiss()
                    }
                    .buttonStyle(.secondary)
                }
                Spacer()
                SettingsLink { Text("Settings…") }.buttonStyle(.ghost)
                Button("Refresh Now") { Task { await state.refresh() } }
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(state.isRefreshing || !state.hasToken)
            }
        }
        .textStyle(.meta)
        .padding(16)
        .frame(width: 340)
    }
}

struct SignInPrompt: View {
    @Environment(AppState.self) private var state
    @State private var cliAccount: String?

    var body: some View {
        ContentUnavailableView {
            Label("Sign in to GitHub", systemImage: "person.crop.circle.badge.questionmark")
        } description: {
            Text("RepoRadar brings your notifications, pull requests and GitHub Actions runs together.")
        } actions: {
            if let cliAccount {
                Button("Use GitHub CLI Account (@\(cliAccount))") { Task { await state.signInWithGitHubCLI() } }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                SettingsLink { Text("Other Ways to Sign In…") }
            } else {
                SettingsLink { Text("Open Settings") }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
            }
        }
        .task { cliAccount = await GitHubCLI.account() }
    }
}

/// Dismissible banner under the toolbar for refresh or action errors; data already shown stays.
struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Tone.red.solid)
                .accessibilityHidden(true)
            Text(message)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Ink.secondary)
        }
        .textStyle(.meta)
        .padding(10)
        .glassEffect(.regular.tint(Tone.red.tint), in: .rect(cornerRadius: 10))
    }
}

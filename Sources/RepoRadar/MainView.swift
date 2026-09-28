import SwiftUI

enum SidebarItem: Hashable {
    case inbox, pulls, actions
    case repo(String)

    var title: String {
        switch self {
        case .inbox: "Inbox"
        case .pulls: "Pull Requests"
        case .actions: "Actions"
        case .repo(let repo): repo
        }
    }
}

struct MainView: View {
    @Environment(AppState.self) private var state
    @AppStorage("detailLayout") private var layout: DetailLayout = .bottom
    @State private var selection: SidebarItem? = .inbox
    @State private var search = ""
    @State private var scope: SearchScope = .all
    @State private var sidebarFilter = ""
    @FocusState private var focus: FocusTarget?

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $selection, filter: $sidebarFilter, focus: $focus)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 340)
        } detail: {
            detail
                .navigationTitle(selection?.title ?? "RepoRadar")
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                ToolbarStatus(selection: $selection)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                RefreshButton()
                layoutButton(.bottom, title: "Detail Below", symbol: "rectangle.bottomhalf.inset.filled")
                layoutButton(.right, title: "Detail on Right", symbol: "rectangle.righthalf.inset.filled")
            }
        }
        .focusedSceneValue(\.sidebarSelection, $selection)
        .onChange(of: state.requestedSection, initial: true) {
            guard let requested = state.requestedSection else { return }
            selection = requested
            state.requestedSection = nil
        }
        .focusedSceneValue(\.focusTarget, Binding(get: { focus }, set: { focus = $0 }))
    }

    @ViewBuilder private var detail: some View {
        if state.hasToken {
            Group {
                switch selection {
                case .inbox, nil: InboxView(search: $search, scope: $scope, focus: $focus)
                case .pulls: PullsView(search: $search, scope: $scope, focus: $focus)
                case .actions: ActionsView(repo: nil, search: $search, scope: $scope, focus: $focus)
                case .repo(let repo): ActionsView(repo: repo, search: $search, scope: $scope, focus: $focus).id(repo)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let error = state.error {
                    ErrorBanner(message: error) { state.error = nil }
                        .padding([.horizontal, .top], 8)
                }
            }
        } else {
            SignInPrompt()
        }
    }

    /// Selecting the active layout again hides the detail pane, like the layout buttons in Rockxy.
    private func layoutButton(_ option: DetailLayout, title: String, symbol: String) -> some View {
        Button(title, systemImage: symbol) { layout = layout == option ? .hidden : option }
            .foregroundStyle(layout == option ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .help(layout == option ? "Hide Detail Pane" : title)
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

/// The centered status pill: who is signed in, what's being watched, and what needs attention.
struct ToolbarStatus: View {
    @Environment(AppState.self) private var state
    @Binding var selection: SidebarItem?
    @State private var showDetails = false

    var body: some View {
        Button { showDetails.toggle() } label: {
            HStack(spacing: 8) {
                StatusDot(color: dotColor)
                Text(summary).lineLimit(1)
                if state.failingCount > 0 {
                    StatusPill(text: "\(state.failingCount) Failing", color: .red)
                }
            }
            .themeFont(.callout)
            .padding(.horizontal, 10)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showDetails, arrowEdge: .bottom) {
            StatusPopover(selection: $selection)
        }
        .help("Account and sync status")
    }

    private var dotColor: Color {
        if !state.hasToken || state.error != nil { return .red }
        return state.isRefreshing ? .orange : .green
    }

    private var summary: String {
        guard state.hasToken else { return "RepoRadar | Signed out" }
        let who = state.login.map { "@\($0)" } ?? "…"
        let activity = state.isRefreshing ? "Updating" : "\(state.repos.count) repositories"
        return "RepoRadar | \(who) | \(activity)"
    }
}

struct StatusPopover: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: SidebarItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow { Text("Account").foregroundStyle(.secondary); Text(state.login.map { "@\($0)" } ?? "—") }
                GridRow {
                    Text("Last update").foregroundStyle(.secondary)
                    Text(state.lastUpdated?.formatted(date: .omitted, time: .standard) ?? "—")
                }
                GridRow {
                    Text("API quota").foregroundStyle(.secondary)
                    Text(state.rateLimit.map { "\($0.remaining) / \($0.limit) left this hour" } ?? "—")
                }
                GridRow { Text("Unread").foregroundStyle(.secondary); Text("\(state.unreadCount)") }
                GridRow { Text("Review requests").foregroundStyle(.secondary); Text("\(state.reviewRequestCount)") }
                GridRow { Text("Failing workflows").foregroundStyle(.secondary); Text("\(state.failingCount)") }
            }
            .monospacedDigit()
            if let error = state.error {
                Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if state.failingCount > 0 {
                    Button("Show Failing") {
                        selection = .actions
                        dismiss()
                    }
                }
                Spacer()
                SettingsLink { Text("Settings…") }
                Button("Refresh Now") { Task { await state.refresh() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(state.isRefreshing || !state.hasToken)
            }
        }
        .themeFont(.callout)
        .padding(16)
        .frame(width: 340)
    }
}

struct Sidebar: View {
    @Environment(AppState.self) private var state
    @Binding var selection: SidebarItem?
    @Binding var filter: String
    var focus: FocusState<FocusTarget?>.Binding
    @State private var collapsedOwners: Set<String> = []

    var body: some View {
        List(selection: $selection) {
            Section("GitHub") {
                Label("Inbox", systemImage: "tray")
                    .badge(state.unreadCount)
                    .tag(SidebarItem.inbox)
                Label("Pull Requests", systemImage: "arrow.triangle.pull")
                    .badge(state.reviewRequestCount)
                    .tag(SidebarItem.pulls)
                Label("Actions", systemImage: "bolt.circle")
                    .badge(state.failingCount)
                    .tag(SidebarItem.actions)
            }
            Section("Repositories") {
                ForEach(owners, id: \.self) { owner in
                    DisclosureGroup(isExpanded: expandedBinding(owner)) {
                        ForEach(repos(of: owner), id: \.self) { repo in
                            RepoRow(repo: repo, latest: state.runsByRepo[repo]?.latestPerWorkflow() ?? [])
                                .tag(SidebarItem.repo(repo))
                        }
                    } label: {
                        Label(owner, systemImage: "person.2")
                            .badge(repos(of: owner).count)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle").foregroundStyle(.secondary)
                TextField("Filter (⇧⌘F)", text: $filter)
                    .textFieldStyle(.plain)
                    .focused(focus, equals: .sidebarFilter)
                    .onExitCommand { filter = "" }
            }
            .themeFont(.callout)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(8)
        }
    }

    private func repos(of owner: String) -> [String] {
        state.repos.filter { repo in
            repo.hasPrefix(owner + "/") && (filter.isEmpty || repo.localizedCaseInsensitiveContains(filter))
        }
    }

    private var owners: [String] {
        Array(Set(state.repos.compactMap { $0.split(separator: "/").first.map(String.init) }))
            .filter { !repos(of: $0).isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func expandedBinding(_ owner: String) -> Binding<Bool> {
        Binding(
            get: { !filter.isEmpty || !collapsedOwners.contains(owner) },
            set: { if $0 { collapsedOwners.remove(owner) } else { collapsedOwners.insert(owner) } }
        )
    }
}

struct RepoRow: View {
    let repo: String
    let latest: [WorkflowRun]

    var body: some View {
        let overall = latest.overall
        Label {
            Text(repo.split(separator: "/").last.map(String.init) ?? repo).lineLimit(1)
        } icon: {
            Image(systemName: overall?.symbol ?? "circle")
                .foregroundStyle(overall?.color ?? .secondary)
        }
        .badge(latest.count(where: { $0.state == .failure }))
        .help(repo)
        .accessibilityLabel("\(repo), \(overall?.label ?? "no runs")")
    }
}

struct SignInPrompt: View {
    var body: some View {
        ContentUnavailableView {
            Label("Sign in to GitHub", systemImage: "person.crop.circle.badge.questionmark")
        } description: {
            Text("RepoRadar brings your notifications, pull requests and GitHub Actions runs together.")
        } actions: {
            SettingsLink { Text("Open Settings") }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
        }
    }
}

/// Floating Liquid Glass banner above the workspace for refresh or action errors.
struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(message)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .themeFont(.callout)
        .padding(10)
        .glassEffect(.regular.tint(.red.opacity(0.2)), in: .rect(cornerRadius: 10))
    }
}

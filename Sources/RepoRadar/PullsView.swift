import SwiftUI

/// Open pull requests that involve you, across every repository.
struct PullsView: View {
    @Environment(AppState.self) private var state
    @Binding var search: String
    @Binding var scope: SearchScope
    var focus: FocusState<FocusTarget?>.Binding
    @SceneStorage("pullRole") private var role: PRRole = .reviewRequested
    @State private var selection: Set<PullItem.ID> = []
    @State private var sortOrder = [KeyPathComparator(\PullItem.updatedAt, order: .reverse)]

    var body: some View {
        Workspace(search: $search, scope: $scope, focus: focus) {
            FilterTabBar(selection: $role, options: PRRole.allCases, title: \.title) { option in
                state.pulls.count(where: { $0.roles.contains(option) })
            }
        } table: {
            PullTable(items: visibleItems, selection: $selection, sortOrder: $sortOrder)
                .overlay { if visibleItems.isEmpty { emptyState } }
        } detail: {
            if selectedItems.count == 1 {
                IssueDetailView(ref: selectedItems[0].pr.ref)
            } else {
                DetailPlaceholder()
            }
        } status: {
            StatusBar(selected: selectedItems.count, visible: visibleItems.count) {
                Button("Open", systemImage: "safari") { state.open(selectedItems.map(\.pr.htmlUrl)) }
                    .disabled(selectedItems.isEmpty)
                Button("Copy Link", systemImage: "link") { state.copyLinks(selectedItems.map(\.pr.htmlUrl)) }
                    .disabled(selectedItems.isEmpty)
            } stats: {
                Label("\(state.reviewRequestCount) to review", systemImage: "eye")
                    .foregroundStyle(state.reviewRequestCount > 0 ? AnyShapeStyle(.purple) : AnyShapeStyle(.secondary))
                Label("\(state.pulls.count) open", systemImage: "arrow.triangle.pull")
                QuotaLabel()
            }
        }
        .focusedSceneValue(\.selectedURLs, selectedItems.map(\.pr.htmlUrl))
    }

    @ViewBuilder private var emptyState: some View {
        if !search.isEmpty {
            ContentUnavailableView.search(text: search)
        } else if state.isRefreshing && state.lastUpdated == nil {
            ProgressView("Loading pull requests…")
        } else {
            ContentUnavailableView(
                role == .reviewRequested ? "No Reviews Waiting" : "No Pull Requests",
                systemImage: "arrow.triangle.pull",
                description: Text("Open pull requests where you're \(role.title.lowercased()) show up here.")
            )
        }
    }

    private var visibleItems: [PullItem] {
        state.pulls
            .filter { $0.roles.contains(role) }
            .filter { scope.matches(search, title: $0.title, repository: $0.repo, person: $0.author, other: ["#\($0.pr.number)"]) }
            .sorted(using: sortOrder)
    }

    private var selectedItems: [PullItem] {
        state.pulls.filter { selection.contains($0.id) }
    }
}

struct PullTable: View {
    @Environment(AppState.self) private var state
    let items: [PullItem]
    @Binding var selection: Set<PullItem.ID>
    @Binding var sortOrder: [KeyPathComparator<PullItem>]
    @SceneStorage("pullTableColumns.v3") private var columns = TableColumnCustomization<PullItem>()

    var body: some View {
        Table(of: PullItem.self, selection: $selection, sortOrder: $sortOrder, columnCustomization: $columns) {
            TableColumn("", value: \.isDraftRank) { item in
                StatusDot(color: item.pr.isDraft ? .gray : .green).help(item.pr.isDraft ? "Draft" : "Open")
            }
            .width(14)
            .customizationID("state")
            TableColumn("#", value: \.number) { Text("\($0.pr.number)").monospacedDigit().foregroundStyle(.secondary) }
                .width(50)
                .alignment(.trailing)
                .customizationID("number")
            TableColumn("Title", value: \.title) { item in
                HStack(spacing: 6) {
                    Text(item.title)
                    if item.pr.isDraft { StatusPill(text: "Draft", color: .gray) }
                }
            }
            .width(min: 200, ideal: 420)
            .customizationID("title")
            TableColumn("Repository", value: \.repo)
                .width(min: 100, ideal: 190)
                .customizationID("repository")
            TableColumn("Author", value: \.author)
                .width(min: 70, ideal: 120)
                .customizationID("author")
            TableColumn("Involvement", value: \.rolesSummary) { item in
                if item.roles.contains(.reviewRequested) {
                    StatusPill(text: "Review Requested", color: .purple)
                } else {
                    Text(item.rolesSummary).foregroundStyle(.secondary)
                }
            }
            .width(min: 90, ideal: 150)
            .customizationID("roles")
            TableColumn("Comments", value: \.comments) { Text("\($0.comments)").monospacedDigit() }
                .width(min: 50, ideal: 70)
                .alignment(.trailing)
                .customizationID("comments")
            TableColumn("Updated", value: \.updatedAt) { item in
                Text(item.updatedAt, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                    .help(item.updatedAt.formatted(date: .abbreviated, time: .standard))
            }
            .width(min: 70, ideal: 90)
            .customizationID("updated")
        } rows: {
            ForEach(items) { item in
                TableRow(item)
            }
        }
        .alternatingRowBackgrounds()
        .contextMenu(forSelectionType: PullItem.ID.self) { ids in
            LinkActions(urls: items.filter { ids.contains($0.id) }.map(\.pr.htmlUrl))
        } primaryAction: { ids in
            state.open(items.filter { ids.contains($0.id) }.map(\.pr.htmlUrl))
        }
    }
}

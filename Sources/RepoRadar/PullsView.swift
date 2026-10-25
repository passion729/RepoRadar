import SwiftUI

/// Open pull requests that involve you, across every repository.
struct PullsView: View {
    @Environment(AppState.self) private var state
    let search: String
    let toolbar: StandardToolbar
    @SceneStorage("pullRole") private var role: PRRole = .reviewRequested
    @SceneStorage("pullListWidth") private var listWidth = 320.0
    @State private var selection: Set<PullItem.ID> = []
    @State private var sortOrder = [KeyPathComparator(\PullItem.updatedAt, order: .reverse)]

    var body: some View {
        SplitPane(size: $listWidth, range: 280...520, minFlexible: 400) {
            VStack(spacing: 0) {
                ScrollView(.horizontal) {
                    Segmented(selection: $role, segments: PRRole.allCases.map { option in
                        Segment(value: option, title: option.shortTitle, count: scopedItems.count(where: { $0.roles.contains(option) }))
                    })
                    .padding(12)
                }
                .scrollIndicators(.never)
                PullTable(items: visibleItems, selection: $selection, sortOrder: $sortOrder)
                    .overlay { if visibleItems.isEmpty { emptyState } }
            }
        } second: {
            if selectedItems.count == 1 {
                IssueDetailView(ref: selectedItems[0].pr.ref)
            } else {
                DetailPlaceholder()
            }
        }
        .focusedSceneValue(\.selectedURLs, selectedItems.map(\.pr.htmlUrl))
        .toolbar { toolbar }
        .onChange(of: state.requestedSelection, initial: true) {
            guard case .pull(let id)? = state.requestedSelection, let pull = state.pulls.first(where: { $0.id == id }) else { return }
            if !pull.roles.contains(role) { role = PRRole.allCases.first(where: pull.roles.contains) ?? role }
            selection = [id]
            state.requestedSelection = nil
        }
        .focusesTable(onChangeOf: selection)
        .autoRead(selection, when: selectedItems.count == 1 && state.needsAttention(selectedItems[0])) {
            state.markSeen(selectedItems.map(\.seenKey))
        }
    }

    @ViewBuilder private var emptyState: some View {
        if !search.isEmpty {
            ContentUnavailableView.search(text: search)
        } else if state.isRefreshing && state.lastUpdated == nil {
            SkeletonRows().frame(maxHeight: .infinity, alignment: .top)
        } else {
            ContentUnavailableView(
                role == .reviewRequested ? "No Reviews Waiting" : "No Pull Requests",
                systemImage: "arrow.triangle.pull",
                description: Text("Open pull requests where you're \(role.title.lowercased()) show up here.")
            )
        }
    }

    private var scopedItems: [PullItem] {
        state.pulls.filter { state.inScope($0.repo) }
    }

    private var visibleItems: [PullItem] {
        scopedItems
            .filter { $0.roles.contains(role) }
            .filter { matchesSearch(search, [$0.title, $0.repo, $0.author, "#\($0.pr.number)"]) }
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

    /// Single selection: dragging across rows moves the selection instead of extending it.
    private var single: Binding<PullItem.ID?> {
        Binding(get: { selection.first }, set: { selection = $0.map { [$0] } ?? [] })
    }

    var body: some View {
        Table(of: PullItem.self, selection: single, sortOrder: $sortOrder, columnCustomization: $columns) {
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
                    Text(item.title).fontWeight(state.needsAttention(item) ? .medium : .regular)
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

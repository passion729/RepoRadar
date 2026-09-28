import SwiftUI

enum InboxFilter: String, CaseIterable, Identifiable {
    case unread, all, reviews, ci

    var id: Self { self }

    var title: String {
        switch self {
        case .unread: "Unread"
        case .all: "All"
        case .reviews: "Review Requests"
        case .ci: "CI Activity"
        }
    }

    func matches(_ item: GitHubNotification) -> Bool {
        switch self {
        case .unread: item.unread
        case .all: true
        case .reviews: item.reason == "review_requested"
        case .ci: item.reason == "ci_activity" || item.subject.type == "CheckSuite"
        }
    }
}

/// GitHub notifications, with Mail-style read / done handling.
struct InboxView: View {
    @Environment(AppState.self) private var state
    @Binding var search: String
    @Binding var scope: SearchScope
    var focus: FocusState<FocusTarget?>.Binding
    @SceneStorage("inboxFilter") private var filter: InboxFilter = .unread
    @State private var selection: Set<GitHubNotification.ID> = []
    @State private var sortOrder = [KeyPathComparator(\GitHubNotification.updatedAt, order: .reverse)]

    var body: some View {
        Workspace(search: $search, scope: $scope, focus: focus) {
            FilterTabBar(selection: $filter, options: InboxFilter.allCases, title: \.title) { option in
                state.notifications.count(where: option.matches)
            }
        } table: {
            NotificationTable(items: visibleItems, selection: $selection, sortOrder: $sortOrder)
                .overlay { if visibleItems.isEmpty { emptyState } }
        } detail: {
            if selectedItems.count == 1, let ref = selectedItems[0].ref {
                IssueDetailView(ref: ref)
            } else if selectedItems.count == 1 {
                NotificationDetail(item: selectedItems[0])
            } else {
                DetailPlaceholder()
            }
        } status: {
            StatusBar(selected: selectedItems.count, visible: visibleItems.count) {
                Button("Mark as Read", systemImage: "envelope.open") { state.markRead(selectedItems) }
                    .disabled(!selectedItems.contains(where: \.unread))
                Button("Mark as Done", systemImage: "checkmark") { state.markDone(selectedItems) }
                    .disabled(selectedItems.isEmpty)
            } stats: {
                Label("\(state.unreadCount) unread", systemImage: "circle.fill")
                    .foregroundStyle(state.unreadCount > 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                Label("\(state.notifications.count) total", systemImage: "tray")
                QuotaLabel()
            }
        }
        .focusedSceneValue(\.selectedNotifications, selectedItems)
        .focusesTable(onChangeOf: selection)
        .focusedSceneValue(\.selectedURLs, selectedItems.map(\.webURL))
    }

    @ViewBuilder private var emptyState: some View {
        if !search.isEmpty {
            ContentUnavailableView.search(text: search)
        } else if state.isRefreshing && state.lastUpdated == nil {
            ProgressView("Loading notifications…")
        } else {
            ContentUnavailableView(
                filter == .unread ? "All Caught Up" : "No Notifications",
                systemImage: "tray",
                description: Text(filter == .unread ? "You have no unread GitHub notifications." : "Nothing matches this filter.")
            )
        }
    }

    private var visibleItems: [GitHubNotification] {
        state.notifications
            .filter { filter.matches($0) || selection.contains($0.id) }  // keep a just-read selection visible
            .filter { scope.matches(search, title: $0.title, repository: $0.repo, person: "", other: [$0.reasonLabel]) }
            .sorted(using: sortOrder)
    }

    private var selectedItems: [GitHubNotification] {
        state.notifications.filter { selection.contains($0.id) }
    }
}

struct NotificationTable: View {
    @Environment(AppState.self) private var state
    let items: [GitHubNotification]
    @Binding var selection: Set<GitHubNotification.ID>
    @Binding var sortOrder: [KeyPathComparator<GitHubNotification>]
    @SceneStorage("notificationTableColumns.v3") private var columns = TableColumnCustomization<GitHubNotification>()

    /// Single selection: dragging across rows moves the selection instead of extending it.
    private var single: Binding<GitHubNotification.ID?> {
        Binding(get: { selection.first }, set: { selection = $0.map { [$0] } ?? [] })
    }

    var body: some View {
        Table(of: GitHubNotification.self, selection: single, sortOrder: $sortOrder, columnCustomization: $columns) {
            TableColumn("", value: \.unreadRank) { item in
                StatusDot(color: item.unread ? .accentColor : .clear)
                    .accessibilityLabel(item.unread ? "Unread" : "Read")
            }
            .width(14)
            .customizationID("unread")
            TableColumn("Type", value: \.subject.type) { item in
                Label(item.typeLabel, systemImage: item.symbol)
                    .foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 110)
            .customizationID("type")
            TableColumn("Title", value: \.title) { item in
                Text(item.title).fontWeight(item.unread ? .medium : .regular)
            }
            .width(min: 200, ideal: 420)
            .customizationID("title")
            TableColumn("Repository", value: \.repo)
                .width(min: 100, ideal: 190)
                .customizationID("repository")
            TableColumn("Reason", value: \.reason) { item in
                if item.reason == "review_requested" {
                    StatusPill(text: item.reasonLabel, color: .purple)
                } else {
                    Text(item.reasonLabel).foregroundStyle(.secondary)
                }
            }
            .width(min: 80, ideal: 130)
            .customizationID("reason")
            TableColumn("Updated", value: \.updatedAt) { item in
                Text(item.updatedAt, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                    .help(item.updatedAt.formatted(date: .abbreviated, time: .standard))
            }
            .width(min: 70, ideal: 90)
            .customizationID("updated")
            TableColumn("") { item in
                RowActions(item: item)
            }
            .width(52)
            .customizationID("rowActions")
        } rows: {
            ForEach(items) { item in
                TableRow(item)
            }
        }
        .alternatingRowBackgrounds()
        .contextMenu(forSelectionType: GitHubNotification.ID.self) { ids in
            let selected = items.filter { ids.contains($0.id) }
            LinkActions(urls: selected.map(\.webURL))
            Divider()
            NotificationActions(items: selected)
        } primaryAction: { ids in
            state.open(items.filter { ids.contains($0.id) }.map(\.webURL))
        }
    }
}

/// Per-row quick actions, like Mail's hover buttons.
struct RowActions: View {
    @Environment(AppState.self) private var state
    let item: GitHubNotification

    var body: some View {
        HStack(spacing: 10) {
            Button("Mark as Read", systemImage: item.unread ? "envelope.open" : "envelope.open.fill") { state.markRead([item]) }
                .disabled(!item.unread)
                .help(item.unread ? "Mark as Read" : "Already read")
            Button("Mark as Done", systemImage: "checkmark.circle") { state.markDone([item]) }
                .help("Mark as Done")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
    }
}

/// Mail's shortcuts: ⇧⌘U toggles read, ⌃⌘A archives (here: marks done).
struct NotificationActions: View {
    @Environment(AppState.self) private var state
    let items: [GitHubNotification]

    var body: some View {
        Button("Mark as Read", systemImage: "envelope.open") { state.markRead(items) }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .disabled(!items.contains(where: \.unread))
        Button("Mark as Done", systemImage: "checkmark") { state.markDone(items) }
            .keyboardShortcut("a", modifiers: [.command, .control])
            .disabled(items.isEmpty)
    }
}

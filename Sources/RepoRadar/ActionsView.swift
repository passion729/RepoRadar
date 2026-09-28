import SwiftUI

enum RunFilter: String, CaseIterable, Identifiable {
    case all, failing, running, passing

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .failing: "Failing"
        case .running: "Running"
        case .passing: "Passing"
        }
    }

    func matches(_ run: WorkflowRun) -> Bool {
        switch self {
        case .all: true
        case .failing: run.state == .failure
        case .running: run.state.isActive
        case .passing: run.state == .success
        }
    }
}

/// Every workflow's latest run (`repo == nil`), or one repository's run history.
struct ActionsView: View {
    @Environment(AppState.self) private var state
    let repo: String?
    @Binding var search: String
    @Binding var scope: SearchScope
    var focus: FocusState<FocusTarget?>.Binding
    @SceneStorage("runFilter") private var filter: RunFilter = .all
    @State private var selection: Set<WorkflowRun.ID> = []
    @State private var sortOrder = [KeyPathComparator(\WorkflowRun.createdAt, order: .reverse)]

    var body: some View {
        Workspace(search: $search, scope: $scope, focus: focus) {
            FilterTabBar(selection: $filter, options: RunFilter.allCases, title: \.title) { option in
                scopedRuns.count(where: option.matches)
            }
        } table: {
            RunTable(runs: visibleRuns, selection: $selection, sortOrder: $sortOrder)
                .overlay { if visibleRuns.isEmpty { emptyState } }
        } detail: {
            if selectedRuns.count == 1 {
                RunDetail(run: selectedRuns[0])
            } else {
                DetailPlaceholder()
            }
        } status: {
            StatusBar(selected: selectedRuns.count, visible: visibleRuns.count) {
                Button("Re-run Failed", systemImage: "exclamationmark.arrow.triangle.2.circlepath") { state.rerunFailedJobs(selectedRuns) }
                    .disabled(!selectedRuns.contains(where: \.state.canRerunFailedJobs))
                Button("Open", systemImage: "safari") { state.open(selectedRuns.map(\.htmlUrl)) }
                    .disabled(selectedRuns.isEmpty)
            } stats: {
                let failing = scopedRuns.count(where: { $0.state == .failure })
                Label("\(failing) failing", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(failing > 0 ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                Label("\(scopedRuns.count(where: \.state.isActive)) running", systemImage: "play.circle")
                QuotaLabel()
            }
        }
        .confirmationDialog(
            state.pendingCancel.count == 1 ? "Cancel this run?" : "Cancel \(state.pendingCancel.count) runs?",
            isPresented: isConfirmingCancel
        ) {
            Button("Cancel Run", role: .destructive) { state.confirmCancel() }
            Button("Keep Running", role: .cancel) {}
        } message: {
            Text("GitHub stops the in-progress jobs. You can re-run them afterwards.")
        }
        .focusedSceneValue(\.selectedRuns, selectedRuns)
        .focusedSceneValue(\.selectedURLs, selectedRuns.map(\.htmlUrl))
    }

    @ViewBuilder private var emptyState: some View {
        if !search.isEmpty {
            ContentUnavailableView.search(text: search)
        } else if state.isRefreshing && state.lastUpdated == nil {
            ProgressView("Loading workflow runs…")
        } else {
            ContentUnavailableView(
                filter == .all ? "No Workflow Runs" : "No \(filter.title) Workflows",
                systemImage: "bolt.circle",
                description: Text(filter == .all ? "Repositories pushed to recently show their runs here." : "Nothing matches this filter.")
            )
        }
    }

    private var isConfirmingCancel: Binding<Bool> {
        Binding(get: { !state.pendingCancel.isEmpty }, set: { if !$0 { state.pendingCancel = [] } })
    }

    /// Runs in scope, before the status filter and search.
    private var scopedRuns: [WorkflowRun] {
        repo.map { state.runsByRepo[$0] ?? [] } ?? state.latestRuns
    }

    private var visibleRuns: [WorkflowRun] {
        scopedRuns
            .filter(filter.matches)
            .filter { run in
                scope.matches(search, title: "\(run.workflowName) \(run.displayTitle)", repository: run.repo,
                              person: run.actorName, other: [run.branchName, run.event])
            }
            .sorted(using: sortOrder)
    }

    private var selectedRuns: [WorkflowRun] {
        scopedRuns.filter { selection.contains($0.id) }
    }
}

struct RunTable: View {
    @Environment(AppState.self) private var state
    let runs: [WorkflowRun]
    @Binding var selection: Set<WorkflowRun.ID>
    @Binding var sortOrder: [KeyPathComparator<WorkflowRun>]
    @SceneStorage("runTableColumns.v3") private var columns = TableColumnCustomization<WorkflowRun>()

    var body: some View {
        Table(of: WorkflowRun.self, selection: $selection, sortOrder: $sortOrder, columnCustomization: $columns) {
            TableColumn("", value: \.state) { StatusDot(color: $0.state.color).help($0.state.label) }
                .width(14)
                .customizationID("dot")
            TableColumn("#", value: \.runNumber) { Text("\($0.runNumber)").monospacedDigit().foregroundStyle(.secondary) }
                .width(44)
                .alignment(.trailing)
                .customizationID("number")
            TableColumn("Workflow", value: \.workflowName)
                .width(min: 90, ideal: 140)
                .customizationID("workflow")
            TableColumn("Title", value: \.displayTitle)
                .width(min: 140, ideal: 320)
                .customizationID("title")
            TableColumn("Repository", value: \.repo)
                .width(min: 100, ideal: 180)
                .customizationID("repository")
            TableColumn("Branch", value: \.branchName) { Text($0.branchName).themeFont(.body, mono: true) }
                .width(min: 70, ideal: 130)
                .customizationID("branch")
            TableColumn("Event", value: \.event)
                .width(min: 60, ideal: 90)
                .defaultVisibility(.hidden)
                .customizationID("event")
            TableColumn("Actor", value: \.actorName)
                .width(min: 60, ideal: 100)
                .defaultVisibility(.hidden)
                .customizationID("actor")
            // Table builders take at most 10 columns; Group lifts the limit.
            Group {
                TableColumn("Started", value: \WorkflowRun.createdAt) { run in
                    Text(run.createdAt, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                        .help(run.createdAt.formatted(date: .abbreviated, time: .standard))
                }
                .width(min: 70, ideal: 90)
                .customizationID("started")
                TableColumn("Duration", value: \WorkflowRun.duration) { run in
                    Text(Duration.seconds(run.duration).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow)))
                        .monospacedDigit()
                }
                .width(min: 56, ideal: 70)
                .alignment(.trailing)
                .customizationID("duration")
                TableColumn("Status", value: \WorkflowRun.state) { RunStatusCell(state: $0.state) }
                    .width(min: 80, ideal: 96)
                    .customizationID("status")
            }
        } rows: {
            ForEach(runs) { run in
                TableRow(run)
            }
        }
        .alternatingRowBackgrounds()
        .contextMenu(forSelectionType: WorkflowRun.ID.self) { ids in
            let selected = runs.filter { ids.contains($0.id) }
            LinkActions(urls: selected.map(\.htmlUrl))
            Divider()
            RunActions(runs: selected)
        } primaryAction: { ids in
            state.open(runs.filter { ids.contains($0.id) }.map(\.htmlUrl))
        }
    }
}

/// Every state is a capsule badge; settled states (cancelled, skipped) use a neutral gray.
struct RunStatusCell: View {
    let state: RunState

    var body: some View {
        StatusPill(text: state.label, color: state.color == .secondary ? .gray : state.color)
    }
}
/// Re-run and cancel. Shared by the context menu and the Run menu so names and shortcuts match.
struct RunActions: View {
    @Environment(AppState.self) private var state
    let runs: [WorkflowRun]

    var body: some View {
        Button("Re-run Failed Jobs", systemImage: "exclamationmark.arrow.triangle.2.circlepath") { state.rerunFailedJobs(runs) }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!runs.contains(where: \.state.canRerunFailedJobs))
        Button("Re-run All Jobs", systemImage: "arrow.triangle.2.circlepath") { state.rerunAllJobs(runs) }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(!runs.contains(where: { !$0.state.isActive }))
        Divider()
        Button("Cancel Run…", systemImage: "stop.circle", role: .destructive) { state.requestCancel(runs) }
            .keyboardShortcut(".")
            .disabled(!runs.contains(where: \.state.isActive))
    }
}

/// Open / copy / share for any selection. Shared by every context menu and the File menu.
struct LinkActions: View {
    @Environment(AppState.self) private var state
    let urls: [URL]

    var body: some View {
        Button("Open in Browser", systemImage: "safari") { state.open(urls) }
            .keyboardShortcut("o")
            .disabled(urls.isEmpty)
        Button(urls.count > 1 ? "Copy Links" : "Copy Link", systemImage: "link") { state.copyLinks(urls) }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(urls.isEmpty)
        if urls.count == 1, let url = urls.first {
            ShareLink(item: url)
        }
    }
}

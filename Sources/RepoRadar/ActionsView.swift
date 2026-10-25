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

    var status: StatusKind? {
        switch self {
        case .failing: .failure
        case .running: .running
        case .passing: .success
        case .all: nil
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

/// Every workflow's latest run, within the sidebar's repository scope.
struct ActionsView: View {
    @Environment(AppState.self) private var state
    let search: String
    let toolbar: StandardToolbar
    @SceneStorage("runFilter") private var filter: RunFilter = .all
    @SceneStorage("workflowListWidth") private var listWidth = 360.0
    @State private var selection: Set<WorkflowRun.ID> = []
    @State private var sortOrder = [KeyPathComparator(\WorkflowRun.createdAt, order: .reverse)]

    var body: some View {
        SplitPane(size: $listWidth, range: 300...560, minFlexible: 400) {
            VStack(spacing: 0) {
                ScrollView(.horizontal) {
                    Segmented(selection: $filter, segments: RunFilter.allCases.map { option in
                        Segment(value: option, title: option.title, count: scopedRuns.count(where: option.matches), status: option.status)
                    })
                    .padding(12)
                }
                .scrollIndicators(.never)
                RunTable(runs: visibleRuns, selection: $selection, sortOrder: $sortOrder)
                    .overlay { if visibleRuns.isEmpty { emptyState } }
            }
        } second: {
            if selectedRuns.count == 1 {
                RunDetail(run: selectedRuns[0])
            } else {
                DetailPlaceholder()
            }
        }
        .toolbar { toolbar }
        .onChange(of: state.requestedSelection, initial: true) {
            guard case .run(let id)? = state.requestedSelection else { return }
            if !scopedRuns.contains(where: { $0.id == id }) { filter = .all }
            selection = [id]
            state.requestedSelection = nil
        }
        .focusedSceneValue(\.selectedRuns, selectedRuns)
        .focusesTable(onChangeOf: selection)
        .autoRead(selection, when: selectedRuns.count == 1 && state.needsAttention(selectedRuns[0])) {
            state.markSeen(selectedRuns.map(\.seenKey))
        }

        .focusedSceneValue(\.selectedURLs, selectedRuns.map(\.htmlUrl))
    }

    @ViewBuilder private var emptyState: some View {
        if !search.isEmpty {
            ContentUnavailableView.search(text: search)
        } else if state.isRefreshing && state.lastUpdated == nil {
            SkeletonRows().frame(maxHeight: .infinity, alignment: .top)
        } else {
            ContentUnavailableView(
                filter == .all ? "No Workflow Runs" : "No \(filter.title) Workflows",
                systemImage: "bolt.circle",
                description: Text(filter == .all ? "Repositories pushed to recently show their runs here." : "Nothing matches this filter.")
            )
        }
    }

    /// Runs in scope, before the status filter and search.
    private var scopedRuns: [WorkflowRun] {
        state.latestRuns.filter { state.inScope($0.repo) }
    }

    private var visibleRuns: [WorkflowRun] {
        scopedRuns
            .filter(filter.matches)
            .filter { matchesSearch(search, [$0.workflowName, $0.displayTitle, $0.repo, $0.actorName, $0.branchName, $0.event]) }
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

    /// Single selection: dragging across rows moves the selection instead of extending it.
    private var single: Binding<WorkflowRun.ID?> {
        Binding(get: { selection.first }, set: { selection = $0.map { [$0] } ?? [] })
    }

    var body: some View {
        Table(of: WorkflowRun.self, selection: single, sortOrder: $sortOrder, columnCustomization: $columns) {
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
            TableColumn("Title", value: \.displayTitle) { run in
                Text(run.displayTitle).fontWeight(state.needsAttention(run) ? .medium : .regular)
            }
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

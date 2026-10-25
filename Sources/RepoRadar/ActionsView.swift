import SwiftUI

/// Actions (A1–A9): workflows on the left (360 pt), the selected run on the right.
struct ActionsView: View {
    @Environment(AppState.self) private var state
    let search: String
    let toolbar: StandardToolbar
    @SceneStorage("runFilter") private var filter: RunFilter = .all
    @SceneStorage("workflowListWidth") private var listWidth = 360.0
    @State private var selection: String?
    /// An older run picked from a workflow's cells; nil shows the workflow's current run.
    @State private var pickedRun: WorkflowRun?
    @State private var requestedJob: Int?
    @State private var showsAllPassing = false
    @FocusState private var isListFocused: Bool

    private var scoped: [WorkflowSummary] {
        Workflows.summaries(state.runsByRepo, defaultBranches: state.defaultBranches, disabled: state.disabledWorkflows)
            .filter { state.inScope($0.repo) }
    }

    var body: some View {
        let scoped = scoped
        let visible = scoped.filter { filter.matches($0) && matchesSearch($0) }
        let selected = scoped.first { $0.id == selection }
        let run = pickedRun ?? selected?.primaryRun
        SplitPane(size: $listWidth, range: 340...520, minFlexible: 520) {
            VStack(spacing: 0) {
                list(visible)
                Rectangle().fill(Theme.separator).frame(height: 1)
                legend
            }
        } second: {
            if let run {
                RunDetailView(run: run, isLatest: pickedRun == nil || pickedRun?.id == selected?.primaryRun.id,
                              initialJob: requestedJob)
                    .id(run.id)
            } else {
                ContentUnavailableView("No Workflow Selected", systemImage: "bolt.circle",
                                       description: Text("Pick a workflow to see its run, graph and logs."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Segmented(selection: $filter, segments: RunFilter.allCases.map { option in
                    Segment(value: option, title: option.title, count: scoped.count(where: option.matches), status: option.status)
                })
            }
            .sharedBackgroundVisibility(.hidden)
            toolbar
        }
        .focusedSceneValue(\.selectedRuns, run.map { [$0] } ?? [])
        .focusedSceneValue(\.selectedURLs, run.map { [$0.htmlUrl] } ?? [])
        .onChange(of: state.requestedSelection, initial: true) { select(state.requestedSelection, in: scoped) }
    }

    // MARK: List (A2, A3)

    @ViewBuilder private func list(_ workflows: [WorkflowSummary]) -> some View {
        if state.lastUpdated == nil && state.hasToken {
            SkeletonRows(rowHeight: 58).padding(8)
            Spacer()
        } else if workflows.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 36)).foregroundStyle(Tone.green.solid)
                Text(filter == .all ? "No workflow runs yet" : "Nothing \(filter.title.lowercased())")
                    .textStyle(.toolbarTitle).foregroundStyle(Theme.Ink.primary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(WorkflowSummary.Group.allCases, id: \.self) { group in
                        let members = workflows.filter { $0.group == group }
                        if !members.isEmpty {
                            HStack(spacing: 6) {
                                Text(group.title)
                                Text("\(members.count)").foregroundStyle(Theme.Ink.tertiary)
                            }
                            .textStyle(.label)
                            .foregroundStyle(Theme.Ink.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
                            .padding(.bottom, 4)
                            // "Passing" past 10 folds away (A2).
                            let shown = group == .passing && !showsAllPassing ? Array(members.prefix(10)) : members
                            ForEach(shown) { workflow in
                                WorkflowRow(workflow: workflow, isSelected: selection == workflow.id,
                                            pickedRun: selection == workflow.id ? pickedRun : nil) {
                                    selection = workflow.id
                                    pickedRun = nil
                                    requestedJob = nil
                                    isListFocused = true
                                } pick: { run in
                                    selection = workflow.id
                                    pickedRun = run.id == workflow.primaryRun.id ? nil : run
                                }
                            }
                            if group == .passing, members.count > 10 {
                                Button(showsAllPassing ? "Show fewer" : "Show \(members.count - 10) more") { showsAllPassing.toggle() }
                                    .buttonStyle(.plain)
                                    .textStyle(.meta)
                                    .foregroundStyle(Theme.Ink.link)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                            }
                        }
                    }
                }
                .padding(8)
            }
            .focusable()
            .focused($isListFocused)
            .focusEffectDisabled()
            .onKeyPress(phases: .down) { handleKey($0, order: workflows.map(\.id)) }
        }
    }

    private var legend: some View {
        let keys = HStack(spacing: 10) {
            ForEach([(StatusKind.success, "passed"), (.failure, "failed"), (.running, "running"), (.waiting, "waiting")], id: \.1) { kind, label in
                HStack(spacing: 4) {
                    if kind == .waiting {
                        RoundedRectangle(cornerRadius: 2).strokeBorder(kind.color, style: StrokeStyle(lineWidth: 1, dash: [2, 1.5]))
                            .frame(width: 8, height: 10)
                    } else {
                        RoundedRectangle(cornerRadius: 2).fill(kind == .running ? Color(hex: 0xF0A020) : kind.color).frame(width: 8, height: 10)
                    }
                    Text(label)
                }
                .fixedSize()
            }
        }
        return ViewThatFits(in: .horizontal) {
            HStack { keys; Spacer(minLength: 4); Text("last 20 runs").foregroundStyle(Theme.Ink.tertiary).fixedSize() }
            HStack { keys; Spacer(minLength: 0) }
        }
        .textStyle(.meta)
        .foregroundStyle(Theme.Ink.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private func matchesSearch(_ workflow: WorkflowSummary) -> Bool {
        let query = JumpQuery(search)
        return (query.repo.map { workflow.repo.localizedCaseInsensitiveContains($0) } ?? true)
            && query.words.allSatisfy { workflow.name.localizedCaseInsensitiveContains($0) || workflow.repo.localizedCaseInsensitiveContains($0) }
    }

    private func handleKey(_ press: KeyPress, order: [String]) -> KeyPress.Result {
        guard !(NSApp.keyWindow?.firstResponder is NSTextView), !order.isEmpty else { return .ignored }
        let delta: Int
        switch (press.key, press.characters) {
        case (.downArrow, _), (_, "j"): delta = 1
        case (.upArrow, _), (_, "k"): delta = -1
        default: return .ignored
        }
        guard press.modifiers.isEmpty || press.key == .downArrow || press.key == .upArrow else { return .ignored }
        let index = selection.flatMap(order.firstIndex) ?? -1
        selection = order[min(max(index + delta, 0), order.count - 1)]
        pickedRun = nil
        requestedJob = nil
        return .handled
    }

    /// Opens a run (and a job) asked for by another page.
    private func select(_ request: SelectionRequest?, in workflows: [WorkflowSummary]) {
        let (runID, jobID): (Int, Int?)
        switch request {
        case .runFilter(let option)?:
            filter = option
            state.requestedSelection = nil
            return
        case .run(let id)?: (runID, jobID) = (id, nil)
        case .job(let run, let job)?: (runID, jobID) = (run, job)
        default: return
        }
        state.requestedSelection = nil
        guard let run = state.runsByRepo.values.joined().first(where: { $0.id == runID }),
              let workflow = workflows.first(where: { $0.repo == run.repo && $0.workflowId == run.workflowId }) else { return }
        if !filter.matches(workflow) { filter = .all }
        selection = workflow.id
        pickedRun = run.id == workflow.primaryRun.id ? nil : run
        requestedJob = jobID
    }
}

/// A workflow (A2, A3): state, name, repository, age; its last 20 default-branch runs and pass rate.
private struct WorkflowRow: View {
    @Environment(AppState.self) private var state
    let workflow: WorkflowSummary
    let isSelected: Bool
    let pickedRun: WorkflowRun?
    let select: () -> Void
    let pick: (WorkflowRun) -> Void
    @State private var isHovered = false

    var body: some View {
        let history = state.history(of: workflow)
        let rate = RunStats.passRate(Array(history.suffix(20)))
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                StatusIcon(workflow.primaryRun.isAwaitingApproval ? .waiting : workflow.primaryRun.state.status)
                Text(workflow.name).textStyle(.rowTitle).foregroundStyle(Theme.Ink.primary).lineLimit(1)
                Text(workflow.repo).textStyle(.meta).foregroundStyle(Theme.Ink.secondary).lineLimit(1).truncationMode(.head)
                Spacer(minLength: 6)
                TimelineView(.periodic(from: .now, by: workflow.latest.state.isActive ? 1 : 60)) { _ in
                    Text(age).textStyle(.meta).foregroundStyle(Theme.Ink.secondary)
                }
            }
            HStack(spacing: 8) {
                RunCells(runs: history, count: 20, cell: CGSize(width: 9, height: 12), spacing: 2, onSelect: pick)
                    .padding(.leading, 22)
                Spacer(minLength: 4)
                Text(rate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(rate.map { RunStats.tone(ofPassRate: $0).text } ?? Theme.Ink.tertiary)
                    .fixedSize()
            }
        }
        .padding(10)
        .background(isSelected ? Theme.Selection.row : isHovered ? Theme.Fill.hover : .clear, in: .rect(cornerRadius: Theme.Radius.row))
        .overlay { RoundedRectangle(cornerRadius: Theme.Radius.row).strokeBorder(isSelected ? Theme.Selection.rowStroke : .clear) }
        .contentShape(.rect)
        .onTapGesture(perform: select)
        .onHover { isHovered = $0 }
        .task(id: workflow.latest.id) { await state.loadHistory(of: workflow) }
        .contextMenu {
            LinkActions(urls: [workflow.primaryRun.htmlUrl])
            Divider()
            RunActions(runs: [workflow.primaryRun])
            Button("Pin \(workflow.repo) to Sidebar", systemImage: "pin") { state.pin(workflow.repo) }
                .disabled(state.pinnedRepos.contains(workflow.repo) || state.pinnedRepos.count >= AppState.maxPins)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(workflow.name), \(workflow.repo), \(workflow.primaryRun.state.label)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(.default, select)
    }

    private var age: String {
        let run = workflow.latest
        if workflow.awaitingApproval != nil, workflow.group == .attention, workflow.latestDefault?.state != .failure { return "waiting" }
        return run.state.isActive ? RunStats.clock(run.duration) : run.createdAt.shortAge()
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

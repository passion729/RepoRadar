import SwiftUI

/// Now (N5–N9): an 80 pt status band over the Needs-you queue (≥ 560) and a 420 pt right column with
/// Running now and Repository health. When the window is too narrow for both, the right column moves into
/// an inspector (⌥⌘I).
struct NowView: View {
    @Environment(AppState.self) private var state
    let toolbar: StandardToolbar
    @SceneStorage("nowRightWidth") private var rightWidth = 420.0
    @SceneStorage("queueFilter") private var filter: QueueFilter = .all
    @SceneStorage("nowInspector") private var showsInspector = false
    @State private var isCompact = false

    var body: some View {
        VStack(spacing: 0) {
            StatusBand(filter: $filter)
            Rectangle().fill(Theme.separator).frame(height: 1)
            if isCompact {
                QueuePane(filter: $filter)
            } else {
                SplitPane(sized: .second, size: $rightWidth, range: 320...520, minFlexible: 560) {
                    QueuePane(filter: $filter)
                } second: {
                    RightColumn()
                }
            }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width < 560 + 1 + 320 } action: { isCompact = $0 }
        .inspector(isPresented: Binding(get: { isCompact && showsInspector }, set: { showsInspector = $0 })) {
            RightColumn()
                .inspectorColumnWidth(min: 320, ideal: 380, max: 460)
        }
        .toolbar {
            if isCompact {
                ToolbarItem(placement: .primaryAction) {
                    Button(showsInspector ? "Hide Running and Health" : "Show Running and Health", systemImage: "sidebar.right") {
                        showsInspector.toggle()
                    }
                    .help("Running now and Repository health (⌥⌘I)")
                }
            }
            toolbar
        }
        .focusedSceneValue(\.inspector, isCompact ? $showsInspector : nil)
    }
}

private struct InspectorKey: FocusedValueKey { typealias Value = Binding<Bool> }

extension FocusedValues {
    /// The Now page's inspector toggle, while the right column is folded into it.
    var inspector: Binding<Bool>? {
        get { self[InspectorKey.self] }
        set { self[InspectorKey.self] = newValue }
    }
}

// MARK: - Status band (N5)

private struct StatusBand: View {
    @Environment(AppState.self) private var state
    @Binding var filter: QueueFilter
    @SceneStorage("runFilter") private var runFilter: RunFilter = .all
    @SceneStorage("inboxFilter") private var inboxFilter: InboxFilter = .unread

    var body: some View {
        let reviews = state.needsYou.filter { $0.category == .review }
        let failing = state.latestRuns.filter { state.inScope($0.repo) && $0.state == .failure }
        let running = state.runningRuns
        let unread = state.notifications.filter { $0.unread && state.inScope($0.repo) }
        HStack(spacing: 0) {
            segment(reviews.count, "Reviews waiting", reviewsDetail(reviews), Tone.blue.text) { filter = .reviews }
            divider
            segment(failing.count, "Failing workflows", failingDetail(failing), Tone.red.text) {
                runFilter = .failing
                state.navigate(to: .actions)
            }
            divider
            segment(running.count, "Running now", runningDetail(running), Tone.amber.text) {
                runFilter = .running
                state.navigate(to: .actions)
            }
            divider
            segment(unread.count, "Unread", unreadDetail(unread), Theme.Ink.primary) {
                inboxFilter = .unread
                state.navigate(to: .inbox)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(height: 80)
        .background(Theme.Surface.pane)
    }

    private var divider: some View {
        Rectangle().fill(Theme.separator).frame(width: 1).padding(.vertical, 14)
    }

    private func segment(_ count: Int, _ title: String, _ detail: String, _ color: Color, action: @escaping () -> Void) -> some View {
        BandSegment(count: count, title: title, detail: count == 0 ? "All clear" : detail, color: color, action: action)
    }

    private func reviewsDetail(_ items: [NeedsYouItem]) -> String {
        guard let oldest = items.min(by: { $0.since < $1.since }), case .review(let pull, _, _) = oldest.kind else { return "" }
        let age = Date().timeIntervalSince(oldest.since)
        let waited = age < 86_400 ? "\(max(1, Int(age / 3600))) h" : "\(Int(age / 86_400)) \(age < 172_800 ? "day" : "days")"
        return "oldest \(waited) · \(pull.repo.split(separator: "/").last ?? "") #\(pull.number)"
    }

    private func failingDetail(_ runs: [WorkflowRun]) -> String {
        let names = runs.sorted { $0.createdAt > $1.createdAt }.map { "\($0.repo.split(separator: "/").last ?? "") \($0.workflowName)" }
        return names.prefix(2).joined(separator: " · ") + (names.count > 2 ? " · +\(names.count - 2)" : "")
    }

    private func runningDetail(_ runs: [WorkflowRun]) -> String {
        let left = runs.compactMap { run in state.usualDuration(of: run).map { RunStats.remaining(elapsed: run.duration, usual: $0) } }
        guard let longest = left.max() else { return "\(runs.count) in progress" }
        return longest <= 60 ? "finishing now" : "all done in about \(Int((longest / 60).rounded())) min"
    }

    private func unreadDetail(_ threads: [GitHubNotification]) -> String {
        let mentions = threads.count { ["mention", "team_mention"].contains($0.reason) }
        let botAuthors = Dictionary(state.pulls.map { (subjectKey($0.repo, $0.number), $0.author) }, uniquingKeysWith: { a, _ in a })
        let bots = threads.count { thread in
            thread.subject.type == "CheckSuite" || thread.subjectKey.flatMap { botAuthors[$0] }.map(Config.botLogins.contains) == true
        }
        return "\(mentions) \(mentions == 1 ? "mention" : "mentions") · \(bots) from bots"
    }
}

private struct BandSegment: View {
    let count: Int
    let title: String
    let detail: String
    let color: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text("\(count)").textStyle(.bigNumber).foregroundStyle(count == 0 ? Theme.Ink.tertiary : color)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).textStyle(.rowTitle).foregroundStyle(Theme.Ink.primary)
                    Text(detail).textStyle(.meta).foregroundStyle(Theme.Ink.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isHovered ? Theme.Fill.hover : .clear, in: .rect(cornerRadius: 12))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("\(count) \(title), \(detail)")
    }
}

// MARK: - Right column

private struct RightColumn: View {
    var body: some View {
        VStack(spacing: 0) {
            RunningNow()
            Rectangle().fill(Theme.separator).frame(height: 1)
            RepositoryHealth()
        }
    }
}

/// Runs in progress (N8): yours first, at most five; cancel asks first; a click opens the run in Actions.
private struct RunningNow: View {
    @Environment(AppState.self) private var state
    @SceneStorage("runFilter") private var runFilter: RunFilter = .all

    var body: some View {
        let runs = state.runningRuns
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Running now").textStyle(.paneTitle).foregroundStyle(Theme.Ink.primary)
                Chip("\(runs.count)", tone: runs.isEmpty ? .neutral : .amber, compact: true)
                Spacer()
                Button("All runs") { showAll() }
                    .buttonStyle(.plain)
                    .textStyle(.meta)
                    .foregroundStyle(Theme.Ink.link)
            }
            if runs.isEmpty {
                Text("Nothing running").textStyle(.meta).foregroundStyle(Theme.Ink.secondary)
            }
            ForEach(runs.prefix(5)) { run in
                RunningRow(run: run)
            }
            if runs.count > 5 {
                Button("+\(runs.count - 5) more") { showAll() }
                    .buttonStyle(.plain)
                    .textStyle(.meta)
                    .foregroundStyle(Theme.Ink.link)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func showAll() {
        runFilter = .running
        state.navigate(to: .actions)
    }
}

private struct RunningRow: View {
    @Environment(AppState.self) private var state
    let run: WorkflowRun
    @State private var jobs: [WorkflowJob] = []
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                StatusIcon(run.state.status)
                Text(run.repo.split(separator: "/").last.map(String.init) ?? run.repo)
                    .textStyle(.rowTitle).foregroundStyle(Theme.Ink.primary)
                Text("\(run.workflowName) · \(run.branchName)")
                    .textStyle(.meta).foregroundStyle(Theme.Ink.secondary).lineLimit(1)
                Spacer(minLength: 4)
                Button("Cancel Run…", systemImage: "xmark") { state.requestCancel([run]) }
                    .buttonStyle(IconButtonStyle(diameter: 26))
                    .help("Cancel run")
            }
            Group {
                if jobs.isEmpty {
                    Capsule().fill(Theme.Fill.subtle).frame(height: 6)
                } else {
                    JobProgress(jobs: jobs)
                }
            }
            .padding(.leading, 22)
            HStack {
                Text(jobs.isEmpty ? run.state.label : "\(jobs.count { !$0.state.isActive }) of \(jobs.count) jobs done")
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(timing)
                }
            }
            .textStyle(.meta)
            .foregroundStyle(Theme.Ink.secondary)
            .padding(.leading, 22)
        }
        .padding(6)
        .background(isHovered ? Theme.Fill.hover : .clear, in: .rect(cornerRadius: 10))
        .padding(-6)
        .contentShape(.rect)
        .onTapGesture { state.navigate(to: .actions, select: .run(run.id)) }
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Cancel Run") { state.requestCancel([run]) }
        .task(id: run.id) {
            // Jobs move on without the run changing, so poll them while the row is visible.
            while !Task.isCancelled {
                if let loaded = try? await GitHubClient.shared.jobs(of: run) { jobs = loaded }
                try? await Task.sleep(for: Config.activeRunRefresh)
            }
        }
    }

    /// "2:10 · usually 3:40", or "6:02 · 2 min slower than usual".
    private var timing: String {
        let elapsed = run.duration
        guard let usual = state.usualDuration(of: run) else { return RunStats.clock(elapsed) }
        return elapsed > usual
            ? "\(RunStats.clock(elapsed)) · \(RunStats.remainingText(elapsed: elapsed, usual: usual))"
            : "\(RunStats.clock(elapsed)) · usually \(RunStats.clock(usual))"
    }
}

/// Default-branch health (N9): pinned repositories, topped up to six with the most recently active ones.
private struct RepositoryHealth: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Repository health").textStyle(.paneTitle).foregroundStyle(Theme.Ink.primary)
                Text("last 16 runs on default branch").textStyle(.meta).foregroundStyle(Theme.Ink.secondary).lineLimit(1)
            }
            VStack(spacing: 7) {
                ForEach(repos, id: \.self) { repo in
                    let runs = state.defaultBranchRuns(of: repo)
                    let rate = RunStats.passRate(Array(runs.suffix(16)))
                    HStack(spacing: 8) {
                        Text(repo.split(separator: "/").last.map(String.init) ?? repo)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.Ink.primary)
                            .lineLimit(1)
                            .frame(width: 104, alignment: .leading)
                            .help(repo)
                        RunCells(runs: runs, count: 16, cell: CGSize(width: 11, height: 18), spacing: 3) { run in
                            state.navigate(to: .actions, select: .run(run.id))
                        }
                        Spacer(minLength: 4)
                        Text(rate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(rate.map { RunStats.tone(ofPassRate: $0).text } ?? Theme.Ink.tertiary)
                            .fixedSize()
                            .accessibilityLabel(rate.map { "Pass rate \(Int(($0 * 100).rounded())) percent" } ?? "No pass rate yet")
                    }
                }
                if repos.isEmpty {
                    Text("No runs yet").textStyle(.meta).foregroundStyle(Theme.Ink.secondary)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 14) {
                legend(Tone.green.solid, "Passed")
                legend(Tone.red.solid, "Failed")
                legend(Color(hex: 0xF0A020), "Running")
                legend(Tone.neutral.solid, "Cancelled")
                Spacer(minLength: 4)
                Text("oldest → newest").fixedSize()
            }
            .lineLimit(1)
            .font(.system(size: 11))
            .foregroundStyle(Theme.Ink.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var repos: [String] {
        if let scope = state.scopeRepo { return [scope] }
        let pinned = state.pinnedRepos
        let active = state.runsByRepo
            .filter { !pinned.contains($0.key) }
            .sorted { ($0.value.first?.createdAt ?? .distantPast) > ($1.value.first?.createdAt ?? .distantPast) }
            .map(\.key)
        return pinned + active.prefix(max(0, 6 - pinned.count))
    }

    private func legend(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9)
            Text(title)
        }
    }
}

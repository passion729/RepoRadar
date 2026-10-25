import AppKit
import SwiftUI

/// One workflow run (A4–A9): header with re-run / cancel, the job graph (196 pt), and the selected job's log.
struct RunDetailView: View {
    @Environment(AppState.self) private var state
    let run: WorkflowRun
    /// False when the run was picked from the cells: the title says so.
    var isLatest = true
    var initialJob: Int?
    @State private var jobs: [WorkflowJob]?
    @State private var declared: [DeclaredJob] = []
    @State private var selectedJob: WorkflowJob.ID?
    @State private var expandedMatrices: Set<String> = []
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RunHeader(run: run, isLatest: isLatest)
            if let jobs {
                JobGraphView(graph: JobGraph(jobs: jobs, declared: declared, expanded: expandedMatrices),
                             selection: $selectedJob) { expandedMatrices.insert($0) }
                    .frame(height: 196)
                    .background(Theme.Fill.subtle.opacity(0.5))
                Rectangle().fill(Theme.separator).frame(height: 1)
                if let job = jobs.first(where: { $0.id == selectedJob }) {
                    JobLogPanel(repo: run.repo, job: job)
                        .id(job.id)
                } else {
                    ContentUnavailableView("No Job Selected", systemImage: "square.stack.3d.up",
                                           description: Text("Pick a job in the graph to read its log."))
                        .frame(maxHeight: .infinity)
                }
            } else if let error {
                ContentUnavailableView("Couldn't Load Jobs", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                SkeletonRows(count: 3, rowHeight: 44).padding(20)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: "\(run.id)-\(run.updatedAt.timeIntervalSince1970)") { await load() }
    }

    private func load() async {
        let client = GitHubClient.shared
        // The workflow file supplies `needs:` for the graph; without it the jobs still show, in one column.
        async let file = try? client.workflowFile(of: run)
        while !Task.isCancelled {
            do {
                let loaded = try await client.jobs(of: run)
                if declared.isEmpty { declared = await file.map(WorkflowYAML.jobs) ?? [] }
                jobs = loaded
                error = nil
                if selectedJob == nil || !loaded.contains(where: { $0.id == selectedJob }) {
                    // The job asked for, else the failing one, else the one still running, else the first.
                    selectedJob = (loaded.first { $0.id == initialJob } ?? loaded.first { $0.state == .failure }
                                   ?? loaded.first { $0.state.isActive } ?? loaded.first)?.id
                }
                guard loaded.contains(where: \.state.isActive) else { return }
            } catch {
                self.error = (error as? GitHubError)?.message ?? error.localizedDescription
                return
            }
            try? await Task.sleep(for: Config.activeRunRefresh)  // jobs move on while the run runs
        }
    }
}

/// Status, workflow and run number, commit title; repository, branch, commit, who and when, result and time;
/// Re-run failed, Re-run all and a menu with Cancel, links and the workflow file (A4).
private struct RunHeader: View {
    @Environment(AppState.self) private var state
    let run: WorkflowRun

    let isLatest: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StatusIcon(run.isAwaitingApproval ? .waiting : run.state.status, size: 18)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(run.workflowName) #\(run.runNumber)").textStyle(.detailTitle).foregroundStyle(Theme.Ink.primary)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if !isLatest { Chip("not latest", tone: .amber, compact: true) }
                    Text(run.displayTitle).textStyle(.toolbarTitle).fontWeight(.regular)
                        .foregroundStyle(Theme.Ink.secondary).lineLimit(1)
                }
                TimelineView(.periodic(from: .now, by: run.state.isActive ? 1 : 60)) { _ in
                    Text(meta).textStyle(.meta).foregroundStyle(Theme.Ink.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if run.state.canRerunFailedJobs {
                Button { state.rerunFailedJobs([run]) } label: {
                    Label { HStack(spacing: 6) { Text("Re-run failed"); Kbd("⇧⌘R") } } icon: { Image(systemName: "arrow.clockwise") }
                }
                .buttonStyle(.primary)
                .requiresPermission(state.writeBlockedReason)
            }
            Button { state.rerunAllJobs([run]) } label: { HStack(spacing: 6) { Text("Re-run all"); Kbd("⌥⌘R") } }
                .buttonStyle(.secondary)
                .disabled(run.state.isActive)
                .requiresPermission(state.writeBlockedReason)
            Menu {
                Button("Cancel Run…", systemImage: "stop.circle") { state.requestCancel([run]) }
                    .disabled(!run.state.isActive || state.writeBlockedReason != nil)
                Divider()
                Button("Copy Link", systemImage: "link") { state.copyLinks([run.htmlUrl]) }
                Button("Open on GitHub", systemImage: "safari") { state.open([run.htmlUrl]) }
                if let workflowFile {
                    Button("View Workflow File", systemImage: "doc.text") { state.open([workflowFile]) }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .buttonStyle(IconButtonStyle())
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    /// "owner/repo · main · a1f3c9e · your push 12 min ago · failed after 4m 12s".
    private var meta: String {
        let who = run.actor?.login == state.login ? "your \(run.event)" : "\(run.actorName) · \(run.event)"
        let result = switch run.state {
        case .running, .queued: run.isAwaitingApproval ? "waiting for approval" : "running for \(run.duration.shortDuration)"
        case .failure: "failed after \(run.duration.shortDuration)"
        case .success: "succeeded in \(run.duration.shortDuration)"
        case .cancelled: "cancelled after \(run.duration.shortDuration)"
        case .skipped: "skipped"
        }
        return [run.repo, run.branchName, run.headSha.map { String($0.prefix(7)) }, "\(who) \(run.createdAt.formatted(.relative(presentation: .named)))", result]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private var workflowFile: URL? {
        guard let path = run.path?.split(separator: "@").first, let sha = run.headSha else { return nil }
        return URL(string: "https://github.com/\(run.repo)/blob/\(sha)/\(path)")
    }
}

// MARK: - Job (A6, A7)

/// Where a pop-out log window points.
struct JobLogRef: Codable, Hashable {
    let repo: String
    let jobID: Int
}

/// A job's header (copy, download, pop out, re-run), its failures, and its log. Logs of running jobs are
/// re-read every 5 seconds.
struct JobLogPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    let repo: String
    let job: WorkflowJob
    var showsPopOut = true
    @State private var raw: String?
    @State private var lines: [LogLine] = []
    @State private var failures: [JobLog.Failure] = []
    @State private var current: Int?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if !failures.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(Array(failures.enumerated()), id: \.offset) { index, failure in
                            Button { current = index } label: {
                                HStack(spacing: 4) {
                                    StatusIcon(.failure, size: 10)
                                    Text(failure.title).lineLimit(1)
                                    if let place = failure.place { Text(place).foregroundStyle(Theme.Ink.tertiary) }
                                }
                                .textStyle(.label)
                                .foregroundStyle(Tone.red.text)
                                .padding(.horizontal, 8)
                                .frame(height: 22)
                                .background(Tone.red.tint, in: .capsule)
                                .overlay { Capsule().strokeBorder(current == index ? Tone.red.solid : .clear) }
                            }
                            .buttonStyle(.plain)
                            .help(failure.detail ?? failure.title)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
            if lines.isEmpty {
                Text(message ?? "Loading the log…")
                    .textStyle(.meta)
                    .foregroundStyle(Theme.Ink.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Surface.log, in: .rect(cornerRadius: Theme.Radius.log))
            } else {
                LogViewer(lines: lines, sections: JobLog.sections(lines, steps: job.steps ?? []),
                          failures: failures.compactMap(\.line), current: $current)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .task(id: job.id) { await load() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            StatusIcon(job.state.status)
            Text(job.name).textStyle(.rowTitle).foregroundStyle(Theme.Ink.primary).lineLimit(1)
            Text([job.runnerName ?? job.labels?.first, job.duration.map(\.shortDuration)].compactMap { $0 }.joined(separator: " · "))
                .textStyle(.meta).foregroundStyle(Theme.Ink.secondary).lineLimit(1)
            Spacer(minLength: 8)
            Group {
                Button("Copy Log", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(raw ?? "", forType: .string)
                }
                .help("Copy the raw log")
                Button("Download Raw Log", systemImage: "arrow.down.to.line") { download() }
                    .help("Save the raw log")
                if showsPopOut {
                    Button("Open in Separate Window", systemImage: "arrow.up.left.and.arrow.down.right") {
                        openWindow(value: JobLogRef(repo: repo, jobID: job.id))
                    }
                    .help("Open the log in its own window")
                }
            }
            .buttonStyle(IconButtonStyle(diameter: 28))
            .disabled(raw == nil)
            Button("Re-run job") { state.rerunJob(job.id, name: job.name, repo: repo) }
                .buttonStyle(.secondary)
                .controlSize(.small)
                .disabled(job.state.isActive)
                .help("Re-run this job and the jobs that depend on it")
                .requiresPermission(state.writeBlockedReason)
        }
    }

    private func load() async {
        let client = GitHubClient.shared
        async let notes = try? client.annotations(checkRun: job.id, repo: repo)
        let annotations = await notes ?? []
        while !Task.isCancelled {
            do {
                let text = try await client.log(ofJob: job.id, repo: repo)
                raw = text
                lines = JobLog.parse(text)
                failures = JobLog.failures(annotations: annotations, lines: lines)
                message = nil
            } catch {
                if job.state.isActive {
                    message = "The log appears as the job runs."
                } else if let ended = job.completedAt, ended < .now.addingTimeInterval(-90 * 86_400) {
                    // GitHub answers an expired log with a bare "Server Error".
                    message = "This log has expired. GitHub keeps logs for 90 days unless the repository sets otherwise."
                } else {
                    message = (error as? GitHubError)?.message ?? error.localizedDescription
                }
            }
            guard job.state.isActive else { return }
            try? await Task.sleep(for: .seconds(5))  // follow a running job's tail
        }
    }

    private func download() {
        guard let raw else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(job.name).log".replacingOccurrences(of: "/", with: "-")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try raw.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            state.toasts.showError(error.localizedDescription)
        }
    }
}

// MARK: - Log viewer (A8, A9)

/// The log by step: passing steps folded, failing steps showing errors with 2 lines either side; a filter, an
/// "All lines" switch, ANSI colors, and a 6 pt minimap of errors and warnings. Rows render lazily.
struct LogViewer: View {
    enum Mode: String { case errors = "Errors + context", all = "All lines" }

    let lines: [LogLine]
    let sections: [LogSection]
    /// Failure line numbers, for ↑↓ and "1 of 3".
    let failures: [Int]
    @Binding var current: Int?
    @State private var mode: Mode = .errors
    @State private var query = ""
    @State private var openSteps: Set<Int> = []
    @State private var closedSteps: Set<Int> = []
    @State private var expandedFolds: Set<Int> = []
    @State private var highlight: Int?
    @State private var position = ScrollPosition(idType: String.self)
    @State private var viewport: ClosedRange<CGFloat> = 0...1
    @FocusState private var isFocused: Bool

    private static let rowHeight: CGFloat = 18

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows, id: \.id) { row in rowView(row) }
                }
                .scrollTargetLayout()
                .padding(.vertical, 6)
                .padding(.trailing, 18)
            }
            .scrollPosition($position)
            .defaultScrollAnchor(.topLeading)
            .onScrollGeometryChange(for: ClosedRange<CGFloat>.self) { geometry in
                let height = max(geometry.contentSize.height, 1)
                let top = geometry.contentOffset.y / height
                return max(0, top)...min(1, max(top, (geometry.contentOffset.y + geometry.containerSize.height) / height))
            } action: { _, range in viewport = range }
            .overlay(alignment: .trailing) { minimap.padding(.trailing, 6).padding(.vertical, 8) }
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onKeyPress(keys: [.upArrow, .downArrow], phases: .down) { press in
                guard !failures.isEmpty else { return .ignored }
                let step = press.key == .downArrow ? 1 : -1
                current = ((current ?? -step) + step + failures.count) % failures.count
                return .handled
            }
        }
        .background(Theme.Surface.log, in: .rect(cornerRadius: Theme.Radius.log))
        .clipShape(.rect(cornerRadius: Theme.Radius.log))
        .environment(\.colorScheme, .dark)
        .onChange(of: current, initial: true) { _, index in
            if let index, failures.indices.contains(index) { jump(to: failures[index]) }
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease").foregroundStyle(Theme.Ink.tertiary)
                TextField("Filter \(lines.count.formatted()) lines", text: $query)
                    .textFieldStyle(.plain)
                    .onExitCommand { query = "" }
            }
            .textStyle(.meta)
            .padding(.horizontal, 10)
            .frame(width: 220, height: 24)
            .background(Color.white.opacity(0.06), in: .capsule)
            ForEach([Mode.errors, .all], id: \.self) { option in
                Button(option.rawValue) { mode = option }
                    .buttonStyle(.plain)
                    .textStyle(.label)
                    .foregroundStyle(mode == option ? Tone.red.text : Theme.Ink.secondary)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(mode == option ? Tone.red.tint : Color.white.opacity(0.06), in: .capsule)
                    .accessibilityAddTraits(mode == option ? .isSelected : [])
            }
            Spacer()
            if !failures.isEmpty {
                Text("\((current ?? 0) + 1) of \(failures.count)").textStyle(.meta).foregroundStyle(Theme.Ink.secondary)
                Button("Previous Failure", systemImage: "chevron.up") {
                    current = ((current ?? 0) - 1 + failures.count) % failures.count
                }
                Button("Next Failure", systemImage: "chevron.down") {
                    current = ((current ?? -1) + 1) % failures.count
                }
            }
        }
        .buttonStyle(IconButtonStyle(diameter: 22))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: Rows

    private enum Row: Identifiable {
        case step(LogSection, isOpen: Bool)
        case line(LogLine)
        case fold(first: Int, count: Int)

        var id: String {
            switch self {
            case .step(let section, _): "s\(section.id)"
            case .line(let line): "l\(line.number)"
            case .fold(let first, _): "f\(first)"
            }
        }
    }

    private var rows: [Row] {
        if !query.isEmpty { return JobLog.filter(lines, query).map(Row.line) }
        var rows: [Row] = []
        for section in sections {
            let open = isOpen(section)
            rows.append(.step(section, isOpen: open))
            guard open else { continue }
            if mode == .all || section.state != .failure {
                rows += section.lines.map(Row.line)
            } else {
                for row in JobLog.rows(section.lines, expanded: expandedFolds) {
                    switch row {
                    case .line(let line): rows.append(.line(line))
                    case .fold(let first, let count): rows.append(.fold(first: first, count: count))
                    }
                }
            }
        }
        return rows
    }

    /// Failing steps open, passing steps folded, unless toggled.
    private func isOpen(_ section: LogSection) -> Bool {
        if openSteps.contains(section.id) { return true }
        if closedSteps.contains(section.id) { return false }
        return section.state == .failure || (sections.count == 1)
    }

    @ViewBuilder private func rowView(_ row: Row) -> some View {
        switch row {
        case .step(let section, let isOpen):
            Button {
                if isOpen { closedSteps.insert(section.id); openSteps.remove(section.id) }
                else { openSteps.insert(section.id); closedSteps.remove(section.id) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.Ink.tertiary).frame(width: 12)
                    StatusIcon(section.state, size: 12)
                    Text(section.name).fontWeight(.semibold).foregroundStyle(Color(hex: 0xE4E4EA))
                    Spacer(minLength: 16)
                    Text(section.state == .skipped && section.lines.isEmpty ? "skipped"
                         : "\(section.lines.count.formatted()) lines" + (section.duration.map { " · \($0.shortDuration)" } ?? ""))
                        .foregroundStyle(Theme.Ink.tertiary)
                }
                .font(.system(size: 11.5, design: .monospaced))
                .padding(.horizontal, 10)
                .frame(height: 22)
                .frame(minWidth: 600, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .id(row.id)
        case .line(let line):
            HStack(spacing: 10) {
                Text("\(line.number)")
                    .foregroundStyle(Color(hex: 0x6B6B73))
                    .frame(width: 48, alignment: .trailing)
                Group {
                    if let ansi = line.ansi { Text(ANSI.attributed(ansi)) } else { Text(line.text) }
                }
                .foregroundStyle(color(line.kind))
                .fixedSize()
            }
            .font(.system(size: 11, design: .monospaced))
            .frame(height: Self.rowHeight)
            .padding(.trailing, 10)
            .frame(minWidth: 600, alignment: .leading)
            .background(background(line))
            .textSelection(.enabled)
            .id(row.id)
        case .fold(let first, let count):
            Button { expandedFolds.insert(first) } label: {
                Text("┄ \(count.formatted()) \(count == 1 ? "line" : "lines") · Show")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.Ink.tertiary)
                    .padding(.leading, 58)
                    .frame(height: 20)
                    .frame(minWidth: 600, alignment: .leading)
                    .overlay(alignment: .bottom) {
                        Rectangle().stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(Color.white.opacity(0.08)).frame(height: 1)
                    }
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .id(row.id)
        }
    }

    private func color(_ kind: LogLine.Kind) -> Color {
        switch kind {
        case .error: Color(hex: 0xFF8F94)
        case .warning: Color(hex: 0xF5B35C)
        case .group: Color(hex: 0xE4E4EA)
        case .command: Color(hex: 0x6FB2FF)
        case .normal: Color(hex: 0xD6D6DC)
        }
    }

    private func background(_ line: LogLine) -> Color {
        if line.number == highlight { return Theme.accent.opacity(0.35) }
        switch line.kind {
        case .error: return Tone.red.solid.opacity(0.2)
        case .warning: return Tone.amber.solid.opacity(0.12)
        default: return .clear
        }
    }

    // MARK: Jumping and the minimap

    /// Opens whatever hides the line, scrolls to it and highlights it for 1.5 s.
    private func jump(to number: Int) {
        query = ""
        if let section = sections.first(where: { $0.lines.contains { $0.number == number } }) {
            openSteps.insert(section.id)
            closedSteps.remove(section.id)
            if mode == .errors, section.state == .failure {
                for case .fold(let first, let count) in JobLog.rows(section.lines, expanded: expandedFolds)
                where (first..<(first + count)).contains(number) {
                    expandedFolds.insert(first)
                }
            }
        }
        highlight = number
        DispatchQueue.main.async { withAnimation(.snappy) { position.scrollTo(id: "l\(number)", anchor: .center) } }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if highlight == number { highlight = nil }
        }
    }

    /// A 6 pt track: error ticks #FF6B70, warning ticks #E8B04A at line ÷ total; a light block for what's in view.
    /// Drag to scroll; click near a tick to jump to its line.
    private var minimap: some View {
        let total = CGFloat(max(lines.last?.number ?? 1, 1))
        let marks = lines.filter { $0.kind == .error || $0.kind == .warning }
        return GeometryReader { proxy in
            let height = proxy.size.height
            ZStack(alignment: .top) {
                Capsule().fill(Color.white.opacity(0.06))
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.16))
                    .frame(height: max(12, height * (viewport.upperBound - viewport.lowerBound)))
                    .offset(y: height * viewport.lowerBound)
                    .frame(maxHeight: .infinity, alignment: .top)
                ForEach(marks) { line in
                    Rectangle()
                        .fill(line.kind == .error ? Color(hex: 0xFF6B70) : Color(hex: 0xE8B04A))
                        .frame(height: 2)
                        .offset(y: height * CGFloat(line.number) / total)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    guard drag.translation.height != 0 else { return }
                    let fraction = min(max(drag.location.y / height, 0), 1)
                    position.scrollTo(y: fraction * contentHeightEstimate)
                }
                .onEnded { drag in
                    guard abs(drag.translation.height) < 2 else { return }
                    // A click: the nearest tick within a few points, else that spot.
                    let number = Int(drag.location.y / height * total)
                    if let mark = marks.min(by: { abs($0.number - number) < abs($1.number - number) }),
                       abs(CGFloat(mark.number - number)) / total * height < 6 {
                        jump(to: mark.number)
                    } else {
                        position.scrollTo(y: min(max(drag.location.y / height, 0), 1) * contentHeightEstimate)
                    }
                })
        }
        .frame(width: 6)
        .accessibilityElement()
        .accessibilityLabel("\(marks.count { $0.kind == .error }) errors, \(marks.count { $0.kind == .warning }) warnings in \(lines.count) lines")
    }

    private var contentHeightEstimate: CGFloat { CGFloat(rows.count) * Self.rowHeight }
}

/// A job's log in its own window (A6).
struct JobLogWindow: View {
    let ref: JobLogRef
    @State private var job: WorkflowJob?
    @State private var error: String?

    var body: some View {
        Group {
            if let job {
                JobLogPanel(repo: ref.repo, job: job, showsPopOut: false)
                    .navigationTitle("\(job.name) — \(ref.repo)")
            } else if let error {
                ContentUnavailableView("Couldn't Load", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ProgressView()
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .task(id: ref) {
            do {
                job = try await GitHubClient.shared.job(ref.jobID, repo: ref.repo)
            } catch {
                self.error = (error as? GitHubError)?.message ?? error.localizedDescription
            }
        }
    }
}

import SwiftUI

/// Needs-you filters (N6). Your own pull requests (can merge, needs changes) show under All.
enum QueueFilter: String, CaseIterable, Identifiable {
    case all, reviews, ci, mentions

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .reviews: "Reviews"
        case .ci: "CI & deploys"
        case .mentions: "Mentions"
        }
    }

    func matches(_ item: NeedsYouItem) -> Bool {
        switch self {
        case .all: true
        case .reviews: item.category == .review
        case .ci: item.category == .ciAndDeploys
        case .mentions: item.category == .mention
        }
    }
}

/// The queue's keyboard actions, published while the list has focus so the Queue menu can list them.
struct QueueCommands {
    let move: (Int) -> Void
    let toggle: () -> Void
    let done: () -> Void
    let snooze: () -> Void
    let primary: () -> Void
    let merge: () -> Void
}

private struct QueueCommandsKey: FocusedValueKey { typealias Value = QueueCommands }

extension FocusedValues {
    var queueCommands: QueueCommands? {
        get { self[QueueCommandsKey.self] }
        set { self[QueueCommandsKey.self] = newValue }
    }
}

// MARK: - Queue pane

struct QueuePane: View {
    @Environment(AppState.self) private var state
    @Binding var filter: QueueFilter
    @State private var selection: String?
    @State private var isExpanded = true
    @State private var snoozing: String?
    /// Set by a row's primary-key handler; the row runs it when it sees the bump.
    @State private var trigger: (id: String, action: QueueKey)?
    @FocusState private var isListFocused: Bool

    private var items: [NeedsYouItem] { state.needsYou.filter(filter.matches) }

    var body: some View {
        let items = items
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Needs you").textStyle(.paneTitle).foregroundStyle(Theme.Ink.primary)
                Spacer()
                Segmented(selection: $filter, segments: QueueFilter.allCases.map { option in
                    Segment(value: option, title: option.title, count: state.needsYou.count(where: option.matches))
                })
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 10)

            if state.lastUpdated == nil && state.hasToken {
                SkeletonRows().padding(.horizontal, 8)
                Spacer()
            } else if items.isEmpty {
                CaughtUp()
            } else {
                list(items)
            }

            Rectangle().fill(Theme.separator).frame(height: 1)
            footer
        }
        .onChange(of: items.map(\.id), initial: true) { _, ids in
            if selection == nil || !ids.contains(selection!) { selection = ids.first }
        }
    }

    private func list(_ items: [NeedsYouItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(items) { item in
                        QueueRow(item: item, isSelected: selection == item.id, isExpanded: isExpanded,
                                 failed: state.failedItems.contains(item.id),
                                 isSnoozing: snoozeBinding(item),
                                 trigger: trigger?.id == item.id ? trigger?.action : nil,
                                 select: { select(item.id) },
                                 handled: { advance(past: item, in: items) })
                            .id(item.id)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .focusable()
            .focused($isListFocused)
            .focusEffectDisabled()
            .onKeyPress(phases: .down) { press in handleKey(press, items: items) }
            .focusedValue(\.queueCommands, isListFocused ? commands(items) : nil)
            .onChange(of: selection) { _, id in
                guard let id else { return }
                withAnimation(.snappy) { proxy.scrollTo(id) }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            hint(["J", "K"], "move")
            hint(["E"], "done")
            hint(["S"], "snooze")
            hint(["↵"], "expand")
            Spacer()
            Text("Sorted by urgency, then age")
        }
        .textStyle(.meta)
        .foregroundStyle(Theme.Ink.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private func hint(_ keys: [String], _ label: String) -> some View {
        HStack(spacing: 5) {
            ForEach(keys, id: \.self) { Kbd($0) }
            Text(label)
        }
    }

    // MARK: Selection and keys

    private func select(_ id: String) {
        if selection == id {
            isExpanded.toggle()
        } else {
            selection = id
            isExpanded = true
        }
        isListFocused = true
    }

    /// After an action the row leaves; the next one (or the previous, at the end) is selected and opened.
    private func advance(past item: NeedsYouItem, in items: [NeedsYouItem]) {
        guard let index = items.firstIndex(of: item) else { return }
        let next = items.indices.contains(index + 1) ? items[index + 1] : index > 0 ? items[index - 1] : nil
        selection = next?.id
        isExpanded = true
        isListFocused = true
    }

    private func move(_ delta: Int, in items: [NeedsYouItem]) {
        guard !items.isEmpty else { return }
        let index = selection.flatMap { id in items.firstIndex { $0.id == id } } ?? -1
        selection = items[min(max(index + delta, 0), items.count - 1)].id
        isExpanded = true
    }

    private func commands(_ items: [NeedsYouItem]) -> QueueCommands {
        QueueCommands(move: { move($0, in: items) },
                      toggle: { isExpanded.toggle() },
                      done: { run(.done) },
                      snooze: { snoozing = selection },
                      primary: { run(.primary) },
                      merge: { run(.merge) })
    }

    /// Single-letter shortcuts work only while the list has focus; a text field keeps its keys.
    private func handleKey(_ press: KeyPress, items: [NeedsYouItem]) -> KeyPress.Result {
        guard !(NSApp.keyWindow?.firstResponder is NSTextView) else { return .ignored }
        if press.key == .return {
            isExpanded.toggle()
            return .handled
        }
        if press.key == .downArrow { move(1, in: items); return .handled }
        if press.key == .upArrow { move(-1, in: items); return .handled }
        if press.modifiers == [.command, .shift], press.characters.lowercased() == "m" {
            run(.merge)
            return .handled
        }
        guard press.modifiers.isEmpty || press.modifiers == .shift else { return .ignored }
        switch press.characters.lowercased() {
        case "j": move(1, in: items)
        case "k": move(-1, in: items)
        case "e": run(.done)
        case "s": snoozing = selection
        case "a", "r": run(.primary)
        default: return .ignored
        }
        return .handled
    }

    private func run(_ action: QueueKey) {
        guard let selection else { return }
        trigger = (selection, action)
        DispatchQueue.main.async { trigger = nil }
    }

    private func snoozeBinding(_ item: NeedsYouItem) -> Binding<Bool> {
        Binding(get: { snoozing == item.id }, set: { snoozing = $0 ? item.id : nil })
    }
}

/// A keyboard action routed to the selected row.
enum QueueKey { case done, primary, merge }

private struct CaughtUp: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(Tone.green.solid)
                .accessibilityHidden(true)
            Text("You're all caught up").textStyle(.toolbarTitle).foregroundStyle(Theme.Ink.primary)
            Text("New reviews, failures and mentions will show up here.")
                .textStyle(.meta)
                .foregroundStyle(Theme.Ink.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Row

private struct QueueRow: View {
    @Environment(AppState.self) private var state
    let item: NeedsYouItem
    let isSelected: Bool
    let isExpanded: Bool
    let failed: Bool
    @Binding var isSnoozing: Bool
    let trigger: QueueKey?
    let select: () -> Void
    let handled: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: select) { header }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.title), \(reason.text), waiting \(item.since.shortAge())")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityHint(isSelected && isExpanded ? "Collapses the row" : "Opens the row")
            if isSelected && isExpanded {
                QueueDetail(item: item, isSnoozing: $isSnoozing, trigger: trigger, handled: handled)
                    .padding(.leading, 56)
                    .padding(.trailing, 14)
                    .padding(.bottom, 14)
                    .transition(.opacity)
            }
        }
        .background(isSelected ? Theme.Selection.row : isHovered ? Theme.Fill.hover : .clear,
                    in: .rect(cornerRadius: Theme.Radius.row))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.row)
                .strokeBorder(failed ? Tone.red.solid.opacity(0.7) : isSelected ? Theme.Selection.rowStroke : .clear, lineWidth: 1)
        }
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Open in Browser", systemImage: "safari") { state.open([item.url]) }
            Button("Copy Link", systemImage: "link") { state.copyLinks([item.url]) }
            Divider()
            Button("Done", systemImage: "checkmark") { state.done(item); handled() }
            Button("Pin \(item.repo) to Sidebar", systemImage: "pin") { state.pin(item.repo) }
                .disabled(state.pinnedRepos.contains(item.repo) || state.pinnedRepos.count >= AppState.maxPins)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            QueueTile(kind: item.kind)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).textStyle(.queueTitle).foregroundStyle(Theme.Ink.primary).lineLimit(1)
                Text(meta).textStyle(.meta).foregroundStyle(Theme.Ink.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Chip(reason.text, tone: reason.tone, compact: true)
                Text(item.since.shortAge()).textStyle(.meta).foregroundStyle(Theme.Ink.secondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
        .contentShape(.rect)
    }

    private var meta: String {
        let short = item.repo
        switch item.kind {
        case .pushFailed(let run):
            return "\(short) · run #\(run.runNumber)" + (run.headSha.map { " · your push \($0.prefix(7))" } ?? "")
        case .deployment(let run, _):
            return "\(short) · \(run.workflowName) · run #\(run.runNumber) · you are a required reviewer"
        case .review(let pull, let direct, let bot):
            return "\(short) #\(pull.number) · \(pull.author)" + (bot ? " · bot" : direct ? "" : " · team review")
        case .mergeable(let pull), .changesRequested(let pull):
            return "\(short) #\(pull.number) · your pull request"
        case .mention(let note):
            return "\(short)" + (note.ref.map { " #\($0.number)" } ?? "") + " · you were mentioned"
        }
    }

    private var reason: (text: String, tone: Tone) {
        switch item.kind {
        case .pushFailed: ("Your push failed", .red)
        case .deployment: ("Approval needed", .amber)
        case .review(_, let direct, _): direct ? ("Review requested", .blue) : ("Team review", .neutral)
        case .mergeable: ("Ready to merge", .green)
        case .mention: ("Mention", .purple)
        case .changesRequested(let pull):
            pull.status?.reviewDecision == "CHANGES_REQUESTED" ? ("Changes requested", .red) : ("Checks failing", .red)
        }
    }
}

/// The 32 pt type tile at the start of a queue row.
private struct QueueTile: View {
    let kind: NeedsYouItem.Kind

    var body: some View {
        Group {
            switch kind {
            case .pushFailed: StatusIcon(.failure, size: 16)
            case .deployment: Image(systemName: "checkmark.shield").foregroundStyle(Tone.amber.text)
            case .review: Image(systemName: "arrow.triangle.pull").foregroundStyle(Tone.blue.text)
            case .mergeable: Image(systemName: "arrow.triangle.merge").foregroundStyle(Tone.green.text)
            case .mention: Text("@").font(.system(size: 15, weight: .bold)).foregroundStyle(Tone.purple.text)
            case .changesRequested: Image(systemName: "exclamationmark.bubble").foregroundStyle(Tone.red.text)
            }
        }
        .font(.system(size: 15, weight: .medium))
        .frame(width: 32, height: 32)
        .background(tone.tint, in: .rect(cornerRadius: 10))
        .accessibilityHidden(true)
    }

    private var tone: Tone {
        switch kind {
        case .pushFailed, .changesRequested: .red
        case .deployment: .amber
        case .review: .blue
        case .mergeable: .green
        case .mention: .purple
        }
    }
}

// MARK: - Inline detail (N7)

private struct QueueDetail: View {
    @Environment(AppState.self) private var state
    let item: NeedsYouItem
    @Binding var isSnoozing: Bool
    let trigger: QueueKey?
    let handled: () -> Void

    var body: some View {
        Group {
            switch item.kind {
            case .review(let pull, let direct, _):
                PullDetailBlock(pull: pull, item: item, mode: .review(youAreRequested: direct), trailing: trailing, trigger: trigger, handled: handled)
            case .mergeable(let pull):
                PullDetailBlock(pull: pull, item: item, mode: .merge, trailing: trailing, trigger: trigger, handled: handled)
            case .changesRequested(let pull):
                PullDetailBlock(pull: pull, item: item, mode: .open, trailing: trailing, trigger: trigger, handled: handled)
            case .pushFailed(let run):
                FailureBlock(run: run, item: item, trailing: trailing, trigger: trigger, handled: handled)
            case .deployment(let run, let environments):
                DeploymentBlock(run: run, environments: environments, item: item, trailing: trailing, trigger: trigger, handled: handled)
            case .mention(let note):
                MentionBlock(note: note, item: item, trailing: trailing, trigger: trigger, handled: handled)
            }
        }
        .onChange(of: trigger) { _, key in
            if key == .done { done() }
        }
    }

    /// Snooze and Done, at the end of every action row.
    private var trailing: AnyView {
        AnyView(HStack(spacing: 8) {
            Spacer(minLength: 0)
            SnoozeButton(isPresented: $isSnoozing) { date in
                state.snooze(item, until: date)
                handled()
            }
            Button(action: done) { HStack(spacing: 6) { Text("Done"); Kbd("E") } }
                .buttonStyle(.ghost)
                .help("Done (E)")
        })
    }

    private func done() {
        state.done(item)
        handled()
    }
}

/// Approve / request changes / comment for a review, Squash and merge for a ready pull request, Open otherwise.
private struct PullDetailBlock: View {
    enum Mode: Equatable { case review(youAreRequested: Bool), merge, open }
    enum Composer { case requestChanges, comment }

    @Environment(AppState.self) private var state
    let pull: PullItem
    let item: NeedsYouItem
    let mode: Mode
    let trailing: AnyView
    let trigger: QueueKey?
    let handled: () -> Void
    @State private var summary: PullSummary?
    @State private var loadError: String?
    @State private var composer: Composer?
    @State private var draft = ""
    @State private var deleteBranch = true
    @FocusState private var isComposing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let summary {
                if mode != .merge, !summary.body.isEmpty {
                    Text(plain(summary.body))
                        .textStyle(.body)
                        .foregroundStyle(Theme.Ink.body)
                        .lineLimit(3)
                }
                HStack(spacing: 8) {
                    ReadinessFlow(steps: Readiness.steps(summary, youAreRequested: mode == .review(youAreRequested: true)))
                    Spacer(minLength: 8)
                    if mode != .merge {
                        ChangeBar(additions: summary.additions, deletions: summary.deletions, files: summary.changedFiles)
                            .fixedSize()
                    }
                }
            } else if let loadError {
                Text(loadError).textStyle(.meta).foregroundStyle(Tone.red.text)
            } else {
                Capsule().fill(Theme.Fill.subtle).frame(width: 280, height: 20)
            }
            if let composer { composerView(composer) }
            actions
        }
        .task(id: pull.pr.updatedAt) {
            do {
                summary = try await GitHubClient.shared.pullSummary(pull.pr.ref)
                loadError = nil
            } catch {
                loadError = (error as? GitHubError)?.message ?? error.localizedDescription
            }
        }
        .onChange(of: trigger) { _, key in
            switch (key, mode) {
            case (.primary, .review): approve()
            case (.merge, .merge), (.primary, .merge): merge()
            default: break
            }
        }
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 8) {
            switch mode {
            case .review:
                Button(action: approve) { Label { HStack(spacing: 6) { Text("Approve"); Kbd("A") } } icon: { Image(systemName: "checkmark") } }
                    .buttonStyle(.primary)
                    .help("Approve (A)")
                Button("Request changes") { open(.requestChanges) }.buttonStyle(.secondary)
                Button("Comment") { open(.comment) }.buttonStyle(.secondary)
                Button("Review files") { state.navigate(to: .pulls, select: .pull(pull.id)) }.buttonStyle(.ghost)
            case .merge:
                Button(action: merge) { HStack(spacing: 6) { Text("Squash and merge"); Kbd("⇧⌘M") } }
                    .buttonStyle(.merge)
                    .help("Squash and merge (⇧⌘M)")
                Toggle("Delete branch", isOn: $deleteBranch)
                    .toggleStyle(.checkbox)
                    .textStyle(.meta)
            case .open:
                Button("Open") { state.navigate(to: .pulls, select: .pull(pull.id)) }.buttonStyle(.primary)
                Button("Open in Browser", systemImage: "safari") { state.open([pull.pr.htmlUrl]) }.buttonStyle(.ghost)
            }
            trailing
        }
    }

    private func composerView(_ kind: Composer) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(kind == .requestChanges ? "What needs to change? (required)" : "Leave a comment…",
                      text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .textStyle(.body)
                .lineLimit(1...6)
                .padding(8)
                .background(Theme.Surface.raised, in: .rect(cornerRadius: Theme.Radius.comment))
                .overlay { RoundedRectangle(cornerRadius: Theme.Radius.comment).strokeBorder(Theme.separator) }
                .focused($isComposing)
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.command) else { return .ignored }
                    submit(kind)
                    return .handled
                }
                .onExitCommand { composer = nil }
            Button(kind == .requestChanges ? "Request changes" : "Comment") { submit(kind) }
                .buttonStyle(.primary)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Submit (⌘↵)")
        }
    }

    private func open(_ kind: Composer) {
        composer = kind
        isComposing = true
    }

    private func submit(_ kind: Composer) {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        state.review(pull, kind == .requestChanges ? .requestChanges : .comment, body: body, item: item)
        draft = ""
        composer = nil
        handled()
    }

    private func approve() {
        state.review(pull, .approve, item: item)
        handled()
    }

    private func merge() {
        guard mode == .merge else { return }
        state.merge(pull, deleteBranch: deleteBranch, item: item)
        handled()
    }

    /// The description without markdown syntax, for a three-line preview.
    private func plain(_ markdown: String) -> String {
        MarkdownBlock.parse(markdown).compactMap { block -> String? in
            switch block {
            case .heading(_, let text), .paragraph(let text), .quote(let text), .listItem(_, _, let text): text
            default: nil
            }
        }
        .joined(separator: " ")
        .replacingOccurrences(of: "**", with: "")
        .replacingOccurrences(of: "`", with: "")
    }
}

/// A failed push: the job chain, the failure from annotations (or `##[error]` log lines), and re-run.
private struct FailureBlock: View {
    @Environment(AppState.self) private var state
    let run: WorkflowRun
    let item: NeedsYouItem
    let trailing: AnyView
    let trigger: QueueKey?
    let handled: () -> Void
    @State private var jobs: [WorkflowJob]?
    @State private var excerpt: Excerpt?

    struct Excerpt {
        let heading: String
        let lines: [LogExcerpt.Line]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let jobs { chain(jobs) }
            if let excerpt {
                VStack(alignment: .leading, spacing: 0) {
                    Text(excerpt.heading).foregroundStyle(Color(hex: 0x8B8B94))
                    ForEach(Array(excerpt.lines.enumerated()), id: \.offset) { _, line in
                        Text(line.isError ? "✕ " + line.text : line.text)
                            .foregroundStyle(line.isError ? Color(hex: 0xFF8A8F) : Color(hex: 0xD6D6DC))
                            .lineLimit(2)
                    }
                }
                .font(.system(size: 11.5, design: .monospaced))
                .lineSpacing(3)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Surface.log, in: .rect(cornerRadius: 12))
            }
            HStack(spacing: 8) {
                Button(action: rerunFailed) {
                    Label { HStack(spacing: 6) { Text("Re-run failed jobs"); Kbd("R") } } icon: { Image(systemName: "arrow.clockwise") }
                }
                .buttonStyle(.primary)
                .help("Re-run failed jobs (R)")
                Button("Re-run all") {
                    state.rerunAllJobs([run], item: item)
                    handled()
                }
                .buttonStyle(.secondary)
                Button("Full log and graph") { state.navigate(to: .actions, select: .run(run.id)) }.buttonStyle(.ghost)
                trailing
            }
        }
        .task(id: run.id) { await load() }
        .onChange(of: trigger) { _, key in if key == .primary { rerunFailed() } }
    }

    private func chain(_ jobs: [WorkflowJob]) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(jobs.prefix(6).enumerated()), id: \.element.id) { index, job in
                if index > 0 {
                    Image(systemName: "arrow.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.Ink.tertiary)
                }
                HStack(spacing: 4) {
                    StatusIcon(job.state.status, size: 12)
                    Text(job.name)
                        .fontWeight(job.state == .failure ? .semibold : .regular)
                        .foregroundStyle(job.state == .skipped ? Theme.Ink.secondary : Theme.Ink.body)
                        .lineLimit(1)
                }
            }
            if jobs.count > 6 { Text("+\(jobs.count - 6)").foregroundStyle(Theme.Ink.tertiary) }
        }
        .textStyle(.meta)
    }

    private func load() async {
        let client = GitHubClient.shared
        guard let loaded = try? await client.jobs(of: run) else { return }
        jobs = loaded
        guard let failed = loaded.first(where: { $0.state == .failure }) else { return }
        let steps = failed.steps ?? []
        let step = steps.first { $0.state == .failure }
        let heading = [failed.name, step.map { "\($0.name) · step \($0.number) of \(steps.count)" }]
            .compactMap { $0 }.joined(separator: " · ")
        // Annotations first (test names with file:line); the log's error lines otherwise.
        let annotations = (try? await client.annotations(checkRun: failed.id, repo: run.repo))?
            .filter { $0.annotationLevel == "failure" } ?? []
        if !annotations.isEmpty {
            excerpt = Excerpt(heading: heading, lines: annotations.prefix(4).enumerated().map { index, note in
                let place = note.path.map { " — \($0)" + (note.startLine.map { ":\($0)" } ?? "") } ?? ""
                return LogExcerpt.Line(number: index, text: (note.title.map { "\($0): " } ?? "") + note.message + place, isError: true)
            })
        } else if let log = try? await client.log(ofJob: failed.id, repo: run.repo),
                  let group = LogExcerpt.errors(in: log, limit: 1).first {
            excerpt = Excerpt(heading: heading, lines: group)
        }
    }

    private func rerunFailed() {
        state.rerunFailedJobs([run], item: item)
        handled()
    }
}

/// A deployment waiting for your review: environments and commit; approve, or reject after confirming.
private struct DeploymentBlock: View {
    @Environment(AppState.self) private var state
    let run: WorkflowRun
    let environments: [PendingDeployment]
    let item: NeedsYouItem
    let trailing: AnyView
    let trigger: QueueKey?
    let handled: () -> Void
    @State private var confirmReject = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                fact("Environment", environments.compactMap(\.environment.name).joined(separator: ", "))
                if let sha = run.headSha {
                    HStack(spacing: 4) {
                        Text("Commit").foregroundStyle(Theme.Ink.secondary)
                        Text(sha.prefix(7)).font(.system(size: 12, design: .monospaced))
                        Text(run.displayTitle).lineLimit(1)
                    }
                }
                fact("Branch", run.branchName)
            }
            .textStyle(.meta)
            .foregroundStyle(Theme.Ink.body)
            HStack(spacing: 8) {
                Button("Approve and deploy", action: approve).buttonStyle(.primary).help("Approve and deploy (A)")
                Button("Reject…") { confirmReject = true }.buttonStyle(.secondary)
                trailing
            }
        }
        .onChange(of: trigger) { _, key in if key == .primary { approve() } }
        .confirmationDialog("Reject this deployment?", isPresented: $confirmReject) {
            Button("Reject Deployment", role: .destructive) {
                state.reviewDeployment(item, approve: false)
                handled()
            }
            Button("Keep Waiting", role: .cancel) {}
        } message: {
            Text("\(run.workflowName) #\(run.runNumber) won't deploy to \(environments.compactMap(\.environment.name).joined(separator: ", ")).")
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(Theme.Ink.secondary)
            Text(value).fontWeight(.semibold)
        }
    }

    private func approve() {
        state.reviewDeployment(item, approve: true)
        handled()
    }
}

/// The comment that mentioned you, with an inline reply (⌘↵ sends).
private struct MentionBlock: View {
    @Environment(AppState.self) private var state
    let note: GitHubNotification
    let item: NeedsYouItem
    let trailing: AnyView
    let trigger: QueueKey?
    let handled: () -> Void
    @State private var comment: IssueComment?
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let comment {
                HStack(alignment: .top, spacing: 10) {
                    Avatar(login: comment.user.login, size: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(comment.user.login).fontWeight(.semibold).foregroundStyle(Theme.Ink.primary)
                        MarkdownText(comment.body ?? "")
                            .foregroundStyle(Theme.Ink.body)
                            .lineLimit(8)
                    }
                    .textStyle(.body)
                }
            }
            HStack(spacing: 8) {
                if let ref = note.ref {
                    TextField(comment.map { "Reply to \($0.user.login)…" } ?? "Reply…", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .textStyle(.body)
                        .lineLimit(1...5)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.Surface.raised, in: .rect(cornerRadius: Theme.Radius.comment))
                        .overlay { RoundedRectangle(cornerRadius: Theme.Radius.comment).strokeBorder(Theme.separator) }
                        .onKeyPress(.return, phases: .down) { press in
                            guard press.modifiers.contains(.command) else { return .ignored }
                            reply(ref)
                            return .handled
                        }
                    Button { reply(ref) } label: { HStack(spacing: 6) { Text("Reply"); Kbd("⌘↵") } }
                        .buttonStyle(.primary)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    Button("Open in Browser", systemImage: "safari") { state.open([note.webURL]) }.buttonStyle(.primary)
                }
                trailing.fixedSize()
            }
        }
        .task(id: note.id) {
            guard let url = note.subject.latestCommentUrl else { return }
            comment = try? await GitHubClient.shared.comment(at: url)
        }
    }

    private func reply(_ ref: IssueRef) {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        state.reply(to: ref, body: body, item: item)
        draft = ""
        handled()
    }
}

// MARK: - Snooze

/// Snooze presets (I4): 1 hour, tomorrow 9:00, next Monday 9:00, or a custom time.
enum SnoozePreset {
    static func dates(now: Date = Date(), calendar: Calendar = .current) -> [(title: String, date: Date)] {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let monday = calendar.nextDate(after: now, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime)!
        return [
            ("1 hour", now.addingTimeInterval(3600)),
            ("Tomorrow 9:00", calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)!),
            ("Next Monday 9:00", calendar.date(bySettingHour: 9, minute: 0, second: 0, of: calendar.startOfDay(for: monday))!),
        ]
    }
}

struct SnoozeButton: View {
    @Binding var isPresented: Bool
    let snooze: (Date) -> Void

    var body: some View {
        Button { isPresented = true } label: { HStack(spacing: 6) { Text("Snooze"); Kbd("S") } }
            .buttonStyle(.ghost)
            .help("Snooze (S)")
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                SnoozeOptions { date in
                    isPresented = false
                    snooze(date)
                }
            }
    }
}

/// The snooze presets plus a custom date, as a popover's content.
struct SnoozeOptions: View {
    let pick: (Date) -> Void
    @State private var custom = Date().addingTimeInterval(3 * 3600)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SnoozePreset.dates(), id: \.title) { preset in
                Button(preset.title) { pick(preset.date) }
                    .buttonStyle(.ghost)
            }
            Divider().padding(.vertical, 4)
            HStack {
                DatePicker("Custom", selection: $custom, in: Date()...)
                    .labelsHidden()
                Button("Snooze") { pick(custom) }.buttonStyle(.secondary).controlSize(.small)
            }
        }
        .padding(10)
    }
}

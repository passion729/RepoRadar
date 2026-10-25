import Charts
import SwiftUI

/// One pull request (P4–P10): header with review actions, the readiness flow with merging, four tabs, and a
/// floating review bar.
struct PullDetailView: View {
    enum Tab: String, CaseIterable { case overview = "Overview", files = "Files", checks = "Checks", conversation = "Conversation" }

    @Environment(AppState.self) private var state
    let pull: PullItem
    @State private var summary: PullSummary?
    @State private var error: String?
    @State private var tab: Tab = .overview
    @State private var reviewEvent: GitHubClient.ReviewEvent = .approve
    @FocusState private var isReviewFocused: Bool

    private var isOwn: Bool { summary?.viewerDidAuthor ?? pull.roles.contains(.authored) }
    private var draftKey: String { "review:" + subjectKey(pull.repo, pull.number) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let summary {
                ReadinessBar(pull: pull, summary: summary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                tabBar(summary)
                Rectangle().fill(Theme.separator).frame(height: 1)
                content(summary)
            } else if let error {
                ContentUnavailableView("Couldn't Load", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                SkeletonRows(count: 4, rowHeight: 60).padding(20)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottom) {
            if summary != nil { reviewBar }
        }
        .task(id: "\(pull.pr.updatedAt.timeIntervalSince1970)-\(state.timelineVersion)") { await load() }
    }

    private func load() async {
        do {
            summary = try await GitHubClient.shared.pullSummary(pull.pr.ref)
            error = nil
            if isOwn { reviewEvent = .comment }
        } catch {
            self.error = (error as? GitHubError)?.message ?? error.localizedDescription
        }
    }

    // MARK: Header (P4)

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                RepoSquare(repo: pull.repo, size: 18)
                Text("\(pull.repo) · #\(pull.number)").textStyle(.meta).foregroundStyle(Theme.Ink.secondary)
                if let summary {
                    Text("\(summary.headRef) → \(summary.baseRef)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.Ink.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 6)
                        .frame(height: 20)
                        .background(Theme.Fill.subtle, in: .rect(cornerRadius: 5))
                }
                Spacer()
                Button("Copy Link", systemImage: "link") { state.copyLinks([pull.pr.htmlUrl]) }
                    .buttonStyle(.icon).help("Copy link (⇧⌘C)")
                Button("Open on GitHub", systemImage: "arrow.up.right.square") { state.open([pull.pr.htmlUrl]) }
                    .buttonStyle(.icon).help("Open on GitHub (⌘O)")
            }
            Text(pull.title).textStyle(.detailTitle).foregroundStyle(Theme.Ink.primary).textSelection(.enabled)
            HStack(spacing: 8) {
                Avatar(login: pull.author, size: 18)
                Text(byline).textStyle(.meta).foregroundStyle(Theme.Ink.secondary).lineLimit(1)
                Spacer(minLength: 8)
                if !isOwn && summary?.state == "OPEN" {
                    Button("Request changes") {
                        reviewEvent = .requestChanges
                        isReviewFocused = true
                    }
                    .buttonStyle(.secondary)
                    Button(action: approve) {
                        Label { HStack(spacing: 6) { Text("Approve"); Kbd("A") } } icon: { Image(systemName: "checkmark") }
                    }
                    .buttonStyle(.primary)
                    .help("Approve (A), with the summary below if you wrote one")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    private var byline: String {
        var parts = ["\(pull.author) opened \(pull.pr.createdAt.formatted(.relative(presentation: .named)))"]
        if let summary {
            parts.append("\(summary.commitCount) \(summary.commitCount == 1 ? "commit" : "commits")")
            if !summary.closingIssues.isEmpty { parts.append("fixes " + summary.closingIssues.joined(separator: ", ")) }
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Tabs (P7)

    private func tabBar(_ summary: PullSummary) -> some View {
        HStack(spacing: 18) {
            ForEach(Tab.allCases, id: \.self) { option in
                let count: Int? = switch option {
                case .overview: nil
                case .files: summary.changedFiles
                case .checks: summary.checks.count
                case .conversation: pull.comments
                }
                Button { tab = option } label: {
                    HStack(spacing: 5) {
                        Text(option.rawValue).fontWeight(tab == option ? .semibold : .regular)
                        if let count { Text("\(count)").foregroundStyle(Theme.Ink.tertiary) }
                    }
                    .textStyle(.rowTitle)
                    .foregroundStyle(tab == option ? Theme.Ink.primary : Theme.Ink.secondary)
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) {
                        if tab == option { Capsule().fill(Theme.accent).frame(height: 2) }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == option ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder private func content(_ summary: PullSummary) -> some View {
        switch tab {
        case .overview: OverviewTab(pull: pull, summary: summary)
        case .files: FilesTab(pull: pull, summary: summary)
        case .checks:
            ScrollView {
                ChecksPanel(pull: pull, checks: summary.checks, showsRerun: true)
                    .padding(20)
                    .padding(.bottom, 80)
            }
        case .conversation: ConversationTab(pull: pull)
        }
    }

    // MARK: Review bar (P10)

    private var reviewDraft: Binding<String> {
        Binding(get: { state.drafts[draftKey] ?? "" }, set: { state.drafts[draftKey] = $0.isEmpty ? nil : $0 })
    }

    private var canSubmit: Bool {
        let text = reviewDraft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return reviewEvent == .approve || !text.isEmpty
    }

    private var reviewBar: some View {
        HStack(spacing: 12) {
            TextField(reviewEvent == .requestChanges ? "What needs to change? (required)" : "Review summary (optional)…",
                      text: reviewDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .textStyle(.body)
                .lineLimit(1...4)
                .focused($isReviewFocused)
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.command) else { return .ignored }
                    submit()
                    return .handled
                }
            Picker("Review", selection: $reviewEvent) {
                Text("Comment").tag(GitHubClient.ReviewEvent.comment)
                if !isOwn {
                    Text("Approve").tag(GitHubClient.ReviewEvent.approve)
                    Text("Request changes").tag(GitHubClient.ReviewEvent.requestChanges)
                }
            }
            .pickerStyle(.radioGroup)
            .horizontalRadioGroupLayout()
            .labelsHidden()
            .textStyle(.meta)
            .fixedSize()
            Button(action: submit) { HStack(spacing: 6) { Text("Submit review"); Kbd("⌘↵") } }
                .buttonStyle(.primary)
                .disabled(!canSubmit)
                .help("Submit review (⌘↵)")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .padding(14)
    }

    private func submit() {
        guard canSubmit else { return }
        let text = reviewDraft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        state.review(pull, reviewEvent, body: text.isEmpty ? nil : text, draftKey: draftKey)
    }

    private func approve() {
        let text = reviewDraft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        state.review(pull, .approve, body: text.isEmpty ? nil : text, draftKey: draftKey)
    }
}

// MARK: - Readiness bar (P5, P6)

private struct ReadinessBar: View {
    @Environment(AppState.self) private var state
    let pull: PullItem
    let summary: PullSummary
    @State private var method = ""
    @State private var deleteBranch = true

    var body: some View {
        let steps = Readiness.steps(summary, youAreRequested: pull.roles.contains(.reviewRequested))
        let blocker = Readiness.blocker(steps)
        HStack(spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                if index > 0 {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.Ink.tertiary)
                }
                card(step, isBlocker: index == blocker)
            }
        }
        .padding(6)
        .background(Theme.Fill.subtle, in: .rect(cornerRadius: 14))
        .onAppear { if method.isEmpty { method = summary.mergeMethods.first ?? "squash" } }
    }

    private func card(_ step: Readiness.Step, isBlocker: Bool) -> some View {
        HStack(spacing: 10) {
            icon(step)
            VStack(alignment: .leading, spacing: 2) {
                Text(title(step.kind)).textStyle(.rowTitle).foregroundStyle(Theme.Ink.primary)
                detail(step)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(isBlocker ? Theme.Surface.raised : .clear, in: .rect(cornerRadius: 10))
        .shadow(color: .black.opacity(isBlocker ? 0.1 : 0), radius: 2, y: 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title(step.kind)): \(step.text)" + (isBlocker ? ", blocking the merge" : ""))
    }

    @ViewBuilder private func icon(_ step: Readiness.Step) -> some View {
        if step.kind == .reviews, step.state != .success, step.state != .failure {
            Text("\(summary.approvedBy.count)/\(summary.approvedBy.count + max(summary.pendingReviewers, 1))")
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(Tone.amber.text)
                .frame(width: 26, height: 26)
                .overlay { Circle().strokeBorder(Tone.amber.solid.opacity(0.6), lineWidth: 2) }
        } else if step.kind == .merge {
            Image(systemName: "arrow.triangle.merge").foregroundStyle(step.state == .success ? Tone.green.solid : Theme.Ink.tertiary)
                .frame(width: 26, height: 26)
        } else {
            StatusIcon(step.state, size: 20).frame(width: 26, height: 26)
        }
    }

    private func title(_ kind: Readiness.Step.Kind) -> String {
        switch kind {
        case .checks: "Checks"
        case .reviews: "Reviews"
        case .branch: "Branch"
        case .merge: "Merge"
        }
    }

    @ViewBuilder private func detail(_ step: Readiness.Step) -> some View {
        switch step.kind {
        case .checks, .reviews:
            Text(step.text.replacingOccurrences(of: "Checks ", with: "").replacingOccurrences(of: "Reviews ", with: ""))
                .textStyle(.meta).foregroundStyle(Theme.Ink.secondary).lineLimit(1)
        case .branch:
            HStack(spacing: 6) {
                Text(step.text).textStyle(.meta).foregroundStyle(Theme.Ink.secondary).lineLimit(1)
                if summary.mergeState == "BEHIND", summary.canWrite {
                    Button("Update branch") { state.updateBranch(pull) }.buttonStyle(.secondary).controlSize(.small)
                }
            }
        case .merge:
            mergeControls(ready: step.state == .success)
        }
    }

    /// Squash and merge (method menu, delete branch) once ready; the auto-merge switch before that.
    /// Hidden without write access.
    @ViewBuilder private func mergeControls(ready: Bool) -> some View {
        if summary.state != "OPEN" {
            Text(summary.state == "MERGED" ? "Merged" : "Closed").textStyle(.meta).foregroundStyle(Theme.Ink.secondary)
        } else if !summary.canWrite {
            Text("No write access").textStyle(.meta).foregroundStyle(Theme.Ink.tertiary)
        } else if ready {
            HStack(spacing: 6) {
                Button { state.merge(pull, method: method, deleteBranch: deleteBranch) } label: {
                    HStack(spacing: 6) { Text(label(method)); Kbd("⇧⌘M") }
                }
                .buttonStyle(.merge)
                .controlSize(.small)
                .keyboardShortcut("m", modifiers: [.command, .shift])
                if summary.mergeMethods.count > 1 {
                    Menu {
                        Picker("Merge method", selection: $method) {
                            ForEach(summary.mergeMethods, id: \.self) { Text(label($0)).tag($0) }
                        }
                        .pickerStyle(.inline)
                    } label: { Image(systemName: "chevron.down") }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .accessibilityLabel("Merge method")
                }
                Toggle("Delete branch", isOn: $deleteBranch).toggleStyle(.checkbox).textStyle(.meta)
            }
        } else {
            let enabled = Binding(get: { summary.autoMergeBy != nil }, set: { on in
                guard on != (summary.autoMergeBy != nil) else { return }
                state.setAutoMerge(on, pull: pull, pullID: summary.id, method: method.isEmpty ? "squash" : method)
            })
            HStack(spacing: 6) {
                Toggle("Auto-merge", isOn: enabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .disabled(!summary.autoMergeAllowed)
                    .textStyle(.meta)
                if let by = summary.autoMergeBy {
                    Text("by \(by)").textStyle(.meta).foregroundStyle(Theme.Ink.secondary)
                }
            }
            .help(summary.autoMergeAllowed ? "Merge on its own once checks and reviews pass"
                                           : "Auto-merge is turned off in this repository's settings")
        }
    }

    private func label(_ method: String) -> String {
        switch method {
        case "merge": "Merge commit"
        case "rebase": "Rebase and merge"
        default: "Squash and merge"
        }
    }
}

// MARK: - Overview (P7, P8, P9)

private struct OverviewTab: View {
    let pull: PullItem
    let summary: PullSummary
    @State private var showsAllFiles = false
    @State private var isWide = true

    var body: some View {
        ScrollView {
            Group {
                if isWide {
                    HStack(alignment: .top, spacing: 24) {
                        main
                        side.frame(width: 300)
                    }
                } else {
                    // Narrow: the checks column moves under the files.
                    VStack(alignment: .leading, spacing: 24) { main; side }
                }
            }
            .padding(20)
            .padding(.bottom, 80)
        }
        .onGeometryChange(for: Bool.self) { $0.size.width >= 760 } action: { isWide = $0 }
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 16) {
            if summary.body.isEmpty {
                Text("No description provided.").italic().foregroundStyle(Theme.Ink.tertiary).textStyle(.body)
            } else {
                MarkdownText(summary.body).textStyle(.body).foregroundStyle(Theme.Ink.body)
            }
            changes
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var changes: some View {
        let files = ChangeList.sorted(summary.files)
        let shown = showsAllFiles ? files : Array(files.prefix(7))
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Changes").textStyle(.rowTitle).foregroundStyle(Theme.Ink.primary)
                Text("+\(summary.additions)").foregroundStyle(Tone.green.text)
                Text("−\(summary.deletions)").foregroundStyle(Tone.red.text)
                Text("· \(summary.changedFiles) files · you've viewed \(summary.files.count(where: \.viewed))")
                    .foregroundStyle(Theme.Ink.secondary)
            }
            .textStyle(.meta)
            ForEach(shown, id: \.path) { file in
                HStack(spacing: 10) {
                    Text(file.path)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Theme.Ink.body)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Group {
                        Text(file.additions > 0 ? "+\(file.additions)" : "").foregroundStyle(Tone.green.text)
                        Text(file.deletions > 0 ? "−\(file.deletions)" : "").foregroundStyle(Tone.red.text)
                    }
                    .font(.system(size: 11.5, design: .monospaced).monospacedDigit())
                    .frame(width: 44, alignment: .trailing)
                    ratioBar(file, in: files)
                }
                .opacity(ChangeList.isGenerated(file.path) ? 0.6 : 1)
                .accessibilityElement(children: .combine)
            }
            if files.count > 7 {
                Button(showsAllFiles ? "Show fewer files" : "Show \(files.count - 7) more files") { showsAllFiles.toggle() }
                    .buttonStyle(.plain)
                    .textStyle(.meta)
                    .foregroundStyle(Theme.Ink.link)
            }
            if summary.changedFiles > summary.files.count {
                Text("\(summary.changedFiles - summary.files.count) more files are listed on GitHub.")
                    .textStyle(.meta).foregroundStyle(Theme.Ink.tertiary)
            }
        }
    }

    /// Green then red, scaled against the biggest file (spec §5), at least 2 pt per colour.
    private func ratioBar(_ file: PullSummary.FileChange, in files: [PullSummary.FileChange]) -> some View {
        let width = ChangeList.barWidth(file, in: files)
        let total = CGFloat(max(1, file.additions + file.deletions))
        return HStack(spacing: 0) {
            Rectangle().fill(Tone.green.solid)
                .frame(width: file.additions == 0 ? 0 : max(2, width * CGFloat(file.additions) / total))
            Rectangle().fill(Tone.red.solid)
                .frame(width: file.deletions == 0 ? 0 : max(2, width * CGFloat(file.deletions) / total))
        }
        .frame(width: 120, height: 6, alignment: .leading)
        .clipShape(.capsule)
    }

    private var side: some View {
        VStack(alignment: .leading, spacing: 24) {
            ChecksPanel(pull: pull, checks: summary.checks, showsRerun: false)
            ReviewersPanel(reviewers: summary.reviewers)
        }
    }
}

/// Every check on one time axis (P8, Swift Charts): failures first, running bars striped amber and growing.
/// Clicking a bar opens its job in Actions.
struct ChecksPanel: View {
    @Environment(AppState.self) private var state
    let pull: PullItem
    let checks: [PullSummary.Check]
    let showsRerun: Bool

    var body: some View {
        let ordered = Readiness.timelineOrder(checks)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Checks").textStyle(.rowTitle).foregroundStyle(Theme.Ink.primary)
                Spacer()
                if let span = span(ordered) {
                    Text("0 – \(Int(ceil(span / 60))) min").textStyle(.meta).foregroundStyle(Theme.Ink.secondary)
                }
            }
            if ordered.isEmpty {
                Text("No checks on the latest commit.").textStyle(.meta).foregroundStyle(Theme.Ink.secondary)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    chart(ordered, now: context.date)
                }
                .frame(height: CGFloat(ordered.count) * 22 + 24)
            }
            if showsRerun {
                ForEach(checks.filter { $0.state == .failure }, id: \.name) { check in
                    HStack(spacing: 8) {
                        StatusIcon(.failure, size: 12)
                        Text(check.name).textStyle(.meta).foregroundStyle(Theme.Ink.body).lineLimit(1)
                        Spacer()
                        if let job = check.jobID, check.runID != nil {
                            Button("Re-run") { state.rerunJob(job, name: check.name, repo: pull.repo) }
                                .buttonStyle(.secondary).controlSize(.small)
                        }
                        if let url = check.url {
                            Button("Open", systemImage: "arrow.up.right.square") { state.open([url]) }
                                .buttonStyle(IconButtonStyle(diameter: 24))
                        }
                    }
                }
            }
        }
    }

    private func span(_ checks: [PullSummary.Check]) -> TimeInterval? {
        guard let start = checks.compactMap(\.startedAt).min() else { return nil }
        let end = checks.map { $0.completedAt ?? Date() }.max() ?? start
        return max(60, end.timeIntervalSince(start))
    }

    private func chart(_ checks: [PullSummary.Check], now: Date) -> some View {
        let origin = checks.compactMap(\.startedAt).min() ?? now
        return Chart(checks, id: \.name) { check in
            let start = (check.startedAt ?? origin).timeIntervalSince(origin) / 60
            let end = ((check.completedAt ?? now).timeIntervalSince(origin)) / 60
            BarMark(xStart: .value("Start", start), xEnd: .value("End", max(end, start + 0.05)), y: .value("Check", check.name))
                .foregroundStyle(check.state == .running || check.state == .waiting ? AnyShapeStyle(StripePattern.amber)
                                                                                    : AnyShapeStyle(check.state.color))
                .cornerRadius(3)
                .annotation(position: .trailing, alignment: .leading, spacing: 4) {
                    Text(RunStats.clock((check.completedAt ?? now).timeIntervalSince(check.startedAt ?? now)))
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(Theme.Ink.secondary)
                }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisValueLabel().font(.system(size: 11)).foregroundStyle(Theme.Ink.body)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(.rect)
                    .onTapGesture { location in
                        guard let plot = proxy.plotFrame, let name: String = proxy.value(atY: location.y - geometry[plot].minY),
                              let check = checks.first(where: { $0.name == name }) else { return }
                        if let run = check.runID {
                            state.navigate(to: .actions, select: .run(run))
                        } else if let url = check.url {
                            state.open([url])
                        }
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(checks.map { "\($0.name) \($0.state.label)" }.joined(separator: ", "))
    }
}

/// Diagonal amber stripes for running checks.
enum StripePattern {
    static let amber = ImagePaint(image: Image(nsImage: image), scale: 1)

    private static let image: NSImage = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
        NSColor(Color(hex: 0xF0A020)).withAlphaComponent(0.55).setFill()
        rect.fill()
        NSColor(Color(hex: 0xF0A020)).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 2.5
        path.move(to: NSPoint(x: -2, y: 2)); path.line(to: NSPoint(x: 2, y: -2))
        path.move(to: NSPoint(x: 0, y: 8)); path.line(to: NSPoint(x: 8, y: 0))
        path.move(to: NSPoint(x: 6, y: 10)); path.line(to: NSPoint(x: 10, y: 6))
        path.stroke()
        return true
    }
}

/// Requested people and teams and what they said (P9); code owners are marked as required.
private struct ReviewersPanel: View {
    @Environment(AppState.self) private var state
    let reviewers: [PullSummary.Reviewer]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reviewers").textStyle(.rowTitle).foregroundStyle(Theme.Ink.primary)
            if reviewers.isEmpty {
                Text("No reviewers yet.").textStyle(.meta).foregroundStyle(Theme.Ink.secondary)
            }
            ForEach(reviewers, id: \.name) { reviewer in
                HStack(spacing: 8) {
                    if reviewer.isTeam {
                        Text(String(reviewer.name.dropFirst().prefix(2)).uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Color(hex: 0x6B6B73), in: .rect(cornerRadius: 6))
                    } else {
                        Avatar(login: reviewer.name, size: 22)
                    }
                    Text(reviewer.name).textStyle(.meta).fontWeight(.semibold).foregroundStyle(Theme.Ink.primary).lineLimit(1)
                    if reviewer.name == state.login { Text("you").textStyle(.meta).foregroundStyle(Theme.Ink.tertiary) }
                    Spacer()
                    if reviewer.isCodeOwner { Chip("Code owner", tone: .amber, compact: true).help("Required: a code owner must approve") }
                    let state = stateChip(reviewer.state)
                    Chip(state.text, tone: state.tone, compact: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func stateChip(_ state: PullSummary.Reviewer.State) -> (text: String, tone: Tone) {
        switch state {
        case .requested: ("Requested", .amber)
        case .approved: ("Approved", .green)
        case .changesRequested: ("Changes requested", .red)
        case .commented: ("Commented", .neutral)
        case .dismissed: ("Dismissed", .neutral)
        }
    }
}

// MARK: - Files (P7)

/// A read-only diff per file, with Viewed synced to GitHub; line comments open GitHub.
private struct FilesTab: View {
    @Environment(AppState.self) private var state
    let pull: PullItem
    let summary: PullSummary
    @State private var files: [PullFile]?
    @State private var viewed: Set<String> = []
    @State private var expanded: Set<String> = []
    @State private var error: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if summary.changedFiles > 300 {
                    Text("This pull request changes \(summary.changedFiles) files; only the first 300 are listed, without diffs past that.")
                        .textStyle(.meta).foregroundStyle(Tone.amber.text)
                }
                if let files {
                    ForEach(files) { file in fileView(file) }
                } else if let error {
                    Text(error).textStyle(.meta).foregroundStyle(Tone.red.text)
                } else {
                    SkeletonRows(count: 4, rowHeight: 40)
                }
            }
            .padding(20)
            .padding(.bottom, 80)
        }
        .task(id: pull.pr.updatedAt) {
            viewed = Set(summary.files.filter(\.viewed).map(\.path))
            do {
                let loaded = try await GitHubClient.shared.pullFiles(pull.pr.ref)
                files = loaded
                // Open what you haven't viewed yet, unless that's a lot.
                let unviewed = loaded.map(\.filename).filter { !viewed.contains($0) }
                expanded = unviewed.count <= 10 ? Set(unviewed) : []
            } catch {
                self.error = (error as? GitHubError)?.message ?? error.localizedDescription
            }
        }
    }

    private func fileView(_ file: PullFile) -> some View {
        let isOpen = expanded.contains(file.filename)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    if isOpen { expanded.remove(file.filename) } else { expanded.insert(file.filename) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isOpen ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .semibold))
                        Text(file.filename).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                    }
                    .foregroundStyle(Theme.Ink.primary)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 8)
                Text("+\(file.additions)").foregroundStyle(Tone.green.text).font(.system(size: 11.5, design: .monospaced))
                Text("−\(file.deletions)").foregroundStyle(Tone.red.text).font(.system(size: 11.5, design: .monospaced))
                Toggle("Viewed", isOn: viewedBinding(file.filename)).toggleStyle(.checkbox).textStyle(.meta)
                Button("Comment on GitHub", systemImage: "text.bubble") {
                    state.open([pull.pr.htmlUrl.appending(path: "files")])
                }
                .buttonStyle(IconButtonStyle(diameter: 24))
                .help("Line comments happen on GitHub")
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Theme.Fill.subtle)
            if isOpen {
                if let patch = file.patch {
                    DiffView(patch: patch)
                } else {
                    Text("Binary or too large to show.").textStyle(.meta).foregroundStyle(Theme.Ink.secondary).padding(12)
                }
            }
        }
        .background(Theme.Surface.raised)
        .clipShape(.rect(cornerRadius: Theme.Radius.comment))
        .overlay { RoundedRectangle(cornerRadius: Theme.Radius.comment).strokeBorder(Theme.separator) }
    }

    /// Marks a file viewed on GitHub; shown at once and put back if GitHub refuses.
    private func viewedBinding(_ path: String) -> Binding<Bool> {
        Binding(get: { viewed.contains(path) }, set: { isViewed in
            if isViewed { viewed.insert(path); expanded.remove(path) } else { viewed.remove(path) }
            Task {
                do {
                    try await GitHubClient.shared.setViewed(path, viewed: isViewed, pullID: summary.id)
                } catch {
                    if isViewed { viewed.remove(path) } else { viewed.insert(path) }
                    state.toasts.showError((error as? GitHubError)?.message ?? error.localizedDescription)
                }
            }
        })
    }
}

/// A unified diff, coloured by line. Long lines scroll sideways instead of wrapping.
private struct DiffView: View {
    let patch: String
    @State private var width: CGFloat = 0

    var body: some View {
        let lines = patch.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        ScrollView(.horizontal) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line.isEmpty ? " " : line)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(line.hasPrefix("@@") ? Theme.Ink.secondary : Theme.Ink.body)
                        .fixedSize()
                        .padding(.horizontal, 12)
                        .frame(minWidth: width, alignment: .leading)
                        .background(background(line))
                }
            }
            .padding(.vertical, 6)
            .textSelection(.enabled)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private func background(_ line: String) -> Color {
        if line.hasPrefix("@@") { return Tone.blue.tint }
        if line.hasPrefix("+") { return Tone.green.tint }
        if line.hasPrefix("-") { return Tone.red.tint }
        return .clear
    }
}

// MARK: - Conversation

private struct ConversationTab: View {
    @Environment(AppState.self) private var state
    let pull: PullItem
    @State private var issue: IssueDetail?
    @State private var timeline: [TimelineEvent] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let issue {
                    ForEach(ThreadEntry.build(issue: issue, timeline: timeline)) { entry in
                        ThreadEntryView(entry: entry, issueAuthor: issue.user.login, login: state.login)
                    }
                } else {
                    SkeletonRows(count: 3, rowHeight: 80)
                }
            }
            .background(alignment: .topLeading) {
                Rectangle().fill(Theme.separator).frame(width: 2).padding(.leading, 32 + 10 + 15)
            }
            .padding(20)
            .padding(.bottom, 80)
        }
        .task(id: state.timelineVersion) {
            async let detail = try? GitHubClient.shared.issue(pull.pr.ref)
            async let events = try? GitHubClient.shared.timeline(pull.pr.ref)
            issue = await detail
            timeline = await events ?? []
        }
    }
}

import SwiftUI

// MARK: - Workflow run: jobs | steps

struct RunDetail: View {
    @Environment(AppState.self) private var state
    let run: WorkflowRun
    @State private var jobs: [WorkflowJob]?
    @State private var error: String?
    @State private var selectedJob: WorkflowJob.ID?
    @State private var declared: [DeclaredJob] = []
    @State private var jobsTab: RunPaneTab = .graph
    @State private var stepsTab: StepPaneTab = .steps

    enum RunPaneTab: String, CaseIterable, Identifiable {
        case graph = "Graph", jobs = "Jobs", summary = "Summary"
        var id: Self { self }
    }

    enum StepPaneTab: String, CaseIterable, Identifiable {
        case steps = "Steps"
        var id: Self { self }
    }

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader {
                RunStatusCell(state: run.state)
                Text("\(run.workflowName) #\(run.runNumber)").fontWeight(.semibold)
                Text("\(run.repo) · \(run.branchName)").themeFont(.body, mono: true).foregroundStyle(.secondary)
                Spacer()
                if run.state.canRerunFailedJobs {
                    Button("Re-run Failed", systemImage: "exclamationmark.arrow.triangle.2.circlepath") { state.rerunFailedJobs([run]) }
                } else if run.state.isActive {
                    Button("Cancel Run…", systemImage: "stop.circle") { state.requestCancel([run]) }
                }
                Button("Open", systemImage: "safari") { state.open([run.htmlUrl]) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Divider()
            PanePair {
                DetailPane(title: "Run", tabs: RunPaneTab.allCases, selection: $jobsTab, tabTitle: \.rawValue) {
                    switch jobsTab {
                    case .graph: graphView
                    case .jobs: jobList
                    case .summary:
                        KeyValueTable(rows: [
                            KeyValue("Title", run.displayTitle),
                            KeyValue("Status", run.state.label),
                            KeyValue("Event", run.event),
                            KeyValue("Actor", run.actorName),
                            KeyValue("Started", run.createdAt.formatted(date: .abbreviated, time: .standard)),
                            KeyValue("Duration", Duration.seconds(run.duration).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))),
                        ])
                    }
                }
            } trailing: {
                DetailPane(title: "Job", tabs: StepPaneTab.allCases, selection: $stepsTab, tabTitle: \.rawValue) {
                    stepList
                }
            }
        }
        .task(id: run) {
            do {
                // The workflow file supplies `needs:` for the graph; without it jobs still show, unconnected.
                async let file = try? GitHubClient.shared.workflowFile(of: run)
                let loaded = try await GitHubClient.shared.jobs(of: run)
                declared = await file.map(WorkflowYAML.jobs) ?? []
                jobs = loaded
                error = nil
                // Show the failing job first, like jumping straight to the failed response.
                selectedJob = (loaded.first { $0.state == .failure } ?? loaded.first)?.id
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    @ViewBuilder private var graphView: some View {
        if let jobs {
            JobGraphView(graph: JobGraph(jobs: jobs, declared: declared),
                         title: run.path.map { String($0.split(separator: "@")[0].split(separator: "/").last ?? "") } ?? run.workflowName,
                         trigger: run.event,
                         selection: $selectedJob)
        } else if let error {
            Text(error).foregroundStyle(.secondary).padding(12)
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private var jobList: some View {
        if let jobs {
            List(jobs, selection: $selectedJob) { job in
                HStack {
                    StatusDot(color: job.state.color)
                    Text(job.name).lineLimit(1)
                    Spacer()
                    if let duration = job.duration {
                        Text(Duration.seconds(duration).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .contextMenu {
                    if let url = job.htmlUrl {
                        Button("Open Job in Browser", systemImage: "safari") { state.open([url]) }
                    }
                }
            }
            .listStyle(.inset)
        } else if let error {
            Text(error).foregroundStyle(.secondary).padding(12)
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private var stepList: some View {
        if let job = jobs?.first(where: { $0.id == selectedJob }) {
            List(job.steps ?? []) { step in
                HStack(spacing: 8) {
                    Text("\(step.number)").monospacedDigit().foregroundStyle(.secondary).frame(width: 22, alignment: .trailing)
                    Image(systemName: step.state.symbol).foregroundStyle(step.state.color)
                    Text(step.name).lineLimit(1)
                }
                .themeFont(.callout)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(step.name), \(step.state.label)")
            }
            .listStyle(.inset)
        } else {
            Text("Select a job to see its steps.").foregroundStyle(.secondary).padding(12)
        }
    }
}

// MARK: - Issue / pull request: overview | activity

struct IssueDetailView: View {
    @Environment(AppState.self) private var state
    let ref: IssueRef
    @State private var detail: Loaded?
    @State private var error: String?
    @State private var infoTab: InfoTab = .overview
    @State private var activityTab: ActivityTab = .checks

    private struct Loaded {
        var issue: IssueDetail
        var pull: PullDetail?
        var checks: [WorkflowRun]
        var comments: [IssueComment]
    }

    enum InfoTab: String, CaseIterable, Identifiable {
        case overview = "Overview", description = "Description"
        var id: Self { self }
    }

    enum ActivityTab: String, CaseIterable, Identifiable {
        case checks = "Checks", comments = "Comments"
        var id: Self { self }
    }

    var body: some View {
        // Not Group: Group applies .task to each child, restarting it on every state switch.
        // Top-aligned and filling, so content taller than the pane can't push its header out of view.
        ZStack(alignment: .top) {
            if let detail {
                content(detail)
            } else if let error {
                ContentUnavailableView("Couldn't Load", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: ref) { await load() }
    }

    private func content(_ detail: Loaded) -> some View {
        VStack(spacing: 0) {
            DetailHeader {
                StatusPill(text: detail.issue.stateLabel, color: detail.issue.stateColor)
                Text("#\(ref.number)").monospacedDigit().foregroundStyle(.secondary)
                Text(detail.issue.title).fontWeight(.semibold)
                Text(ref.repo).foregroundStyle(.secondary)
                Spacer()
                Button("Open", systemImage: "safari") { state.open([detail.issue.htmlUrl]) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            Divider()
            PanePair {
                DetailPane(title: ref.isPullRequest ? "Pull Request" : "Issue", tabs: InfoTab.allCases,
                           selection: $infoTab, tabTitle: \.rawValue) {
                    switch infoTab {
                    case .overview: overview(detail)
                    case .description:
                        ScrollView {
                            MarkdownText(detail.issue.body ?? "No description provided.").padding(12)
                        }
                    }
                }
            } trailing: {
                DetailPane(title: "Activity", tabs: ref.isPullRequest ? ActivityTab.allCases : [.comments],
                           selection: $activityTab, tabTitle: { tab in
                               tab == .checks ? "Checks \(detail.checks.count)" : "Comments \(detail.comments.count)"
                           }) {
                    switch ref.isPullRequest ? activityTab : .comments {
                    case .checks: checks(detail.checks)
                    case .comments: comments(detail.comments)
                    }
                }
            }
        }
    }

    private func overview(_ detail: Loaded) -> some View {
        var rows = [
            KeyValue("Repository", ref.repo),
            KeyValue("Author", detail.issue.user.login),
            KeyValue("Opened", detail.issue.createdAt.formatted(date: .abbreviated, time: .shortened)),
            KeyValue("State", detail.issue.stateLabel),
        ]
        if let pull = detail.pull {
            rows += [
                KeyValue("Branch", "\(pull.head.ref) → \(pull.base.ref)"),
                KeyValue("Changes", "+\(pull.additions) −\(pull.deletions) in \(pull.changedFiles) files"),
                KeyValue("Reviewers", pull.requestedReviewers.isEmpty ? "—" : pull.requestedReviewers.map(\.login).joined(separator: ", ")),
            ]
        }
        rows.append(KeyValue("Labels", detail.issue.labels.isEmpty ? "—" : detail.issue.labels.map(\.name).joined(separator: ", ")))
        return KeyValueTable(rows: rows)
    }

    @ViewBuilder private func checks(_ runs: [WorkflowRun]) -> some View {
        if runs.isEmpty {
            Text("No workflow runs for the latest commit.").foregroundStyle(.secondary).padding(12)
        } else {
            List(runs) { run in
                HStack {
                    StatusDot(color: run.state.color)
                    Text(run.workflowName)
                    Spacer()
                    RunStatusCell(state: run.state)
                }
                .contentShape(.rect)
                .onTapGesture(count: 2) { state.open([run.htmlUrl]) }  // double-click opens, like the tables
                .contextMenu { LinkActions(urls: [run.htmlUrl]) }
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder private func comments(_ comments: [IssueComment]) -> some View {
        if comments.isEmpty {
            Text("No comments yet.").foregroundStyle(.secondary).padding(12)
        } else {
            List(comments) { comment in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(comment.user.login).fontWeight(.semibold)
                        Text(comment.createdAt, format: .relative(presentation: .named)).foregroundStyle(.secondary)
                    }
                    .themeFont(.callout)
                    MarkdownText(comment.body ?? "")
                }
                .padding(.vertical, 4)
            }
            .listStyle(.inset)
        }
    }

    private func load() async {
        let client = GitHubClient.shared
        do {
            async let issue = client.issue(ref)
            async let comments = client.comments(ref)
            var loaded = Loaded(issue: try await issue, pull: nil, checks: [], comments: try await comments)
            if ref.isPullRequest {
                let pull = try await client.pull(ref)
                loaded.pull = pull
                loaded.checks = (try? await client.runs(of: ref.repo, headSHA: pull.head.sha).latestPerWorkflow()) ?? []
            }
            detail = loaded
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Releases, discussions, CI suites and other threads without an issue page.
/// Releases, discussions and other threads without an issue page. CI threads resolve to their
/// workflow run and show the full run detail (graph, jobs, steps).
struct NotificationDetail: View {
    @Environment(AppState.self) private var state
    let item: GitHubNotification
    @State private var run: WorkflowRun?
    @State private var isResolving = false

    var body: some View {
        // Not Group: Group applies .task to each child, restarting it on every state switch.
        // Top-aligned and filling, so content taller than the pane can't push its header out of view.
        ZStack(alignment: .top) {
            if let run {
                RunDetail(run: run)
            } else if isResolving {
                ProgressView("Finding workflow run…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                summary
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: item) {
            run = nil
            guard item.workflowRunHint != nil else { return }
            isResolving = true
            run = try? await GitHubClient.shared.run(for: item)
            isResolving = false
        }
    }

    private var summary: some View {
        VStack(spacing: 0) {
            DetailHeader {
                Label(item.typeLabel, systemImage: item.symbol).foregroundStyle(.secondary)
                Text(item.title).fontWeight(.semibold)
                Spacer()
                Button("Open", systemImage: "safari") { state.open([item.webURL]) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            Divider()
            KeyValueTable(rows: [
                KeyValue("Repository", item.repo),
                KeyValue("Reason", item.reasonLabel),
                KeyValue("Updated", item.updatedAt.formatted(date: .abbreviated, time: .standard)),
                KeyValue("Link", item.webURL.absoluteString),
            ])
        }
    }
}


extension Color {
    /// GitHub label colors come as "rrggbb".
    init(hex: String) {
        let value = UInt32(hex, radix: 16) ?? 0x808080
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

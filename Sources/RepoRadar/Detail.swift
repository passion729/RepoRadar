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

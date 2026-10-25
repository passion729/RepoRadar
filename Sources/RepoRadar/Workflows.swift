import Foundation

/// One workflow of one repository, as the Actions list shows it (A2).
struct WorkflowSummary: Identifiable, Hashable {
    enum Group: Int, CaseIterable, Comparable {
        case attention, running, passing

        var title: String {
            switch self {
            case .attention: "Needs attention"
            case .running: "Running"
            case .passing: "Passing"
            }
        }

        static func < (a: Group, b: Group) -> Bool { a.rawValue < b.rawValue }
    }

    let repo: String
    let workflowId: Int
    let name: String
    /// The newest run on any branch.
    let latest: WorkflowRun
    /// The newest run on the default branch.
    let latestDefault: WorkflowRun?
    /// A run paused for a deployment review, if any.
    let awaitingApproval: WorkflowRun?
    let group: Group

    var id: String { Workflows.key(repo: repo, workflowId: workflowId) }

    /// The run the detail opens: what put it in its group.
    var primaryRun: WorkflowRun {
        switch group {
        case .attention: awaitingApproval ?? latestDefault ?? latest
        case .running, .passing: latest
        }
    }
}

/// Actions filters (A1).
enum RunFilter: String, CaseIterable, Identifiable {
    case all, failing, running, waiting

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .failing: "Failing"
        case .running: "Running"
        case .waiting: "Waiting"
        }
    }

    var status: StatusKind? {
        switch self {
        case .all: nil
        case .failing: .failure
        case .running: .running
        case .waiting: .waiting
        }
    }

    func matches(_ workflow: WorkflowSummary) -> Bool {
        switch self {
        case .all: true
        case .failing: workflow.latestDefault?.state == .failure
        case .running: workflow.latest.state == .running
        case .waiting: workflow.awaitingApproval != nil || workflow.latest.state == .queued
        }
    }
}

enum Workflows {
    static func key(repo: String, workflowId: Int) -> String { "\(repo):\(workflowId)" }

    /// Every workflow with runs, grouped: Needs attention (default branch failing, or a deployment waiting for
    /// review), Running, Passing; newest first within a group.
    /// Disabled workflows are left out (A2).
    static func summaries(_ runsByRepo: [String: [WorkflowRun]], defaultBranches: [String: String],
                          disabled: Set<String> = []) -> [WorkflowSummary] {
        var result: [WorkflowSummary] = []
        for (repo, runs) in runsByRepo {
            let branch = defaultBranches[repo]
            for (id, workflowRuns) in Dictionary(grouping: runs, by: \.workflowId) where !disabled.contains(key(repo: repo, workflowId: id)) {
                let newestFirst = workflowRuns.sorted { $0.createdAt > $1.createdAt }
                let latest = newestFirst[0]
                let latestDefault = newestFirst.first { branch == nil || $0.headBranch == branch }
                let awaiting = newestFirst.first(where: \.isAwaitingApproval)
                let group: WorkflowSummary.Group = if latestDefault?.state == .failure || awaiting != nil {
                    .attention
                } else if latest.state.isActive {
                    .running
                } else {
                    .passing
                }
                result.append(WorkflowSummary(repo: repo, workflowId: id, name: latest.workflowName, latest: latest,
                                              latestDefault: latestDefault, awaitingApproval: awaiting, group: group))
            }
        }
        return result.sorted { ($0.group, $1.latest.createdAt, $0.id) < ($1.group, $0.latest.createdAt, $1.id) }
    }
}

extension JobGraph {
    /// A column's title: the common leading word of its jobs' names ("Build", "Test"), or "Level n".
    static func columnTitle(_ names: [String], level: Int) -> String {
        guard names.count > 1 else { return "Level \(level)" }
        let words = names.map(Self.leadingWord)
        if let first = words.first, words.allSatisfy({ $0 == first }), first.count > 1 { return first }
        return "Level \(level)"
    }

    /// "build (macos-26)" → "Build"; "unit-tests" → "Unit".
    private static func leadingWord(_ name: String) -> String {
        let word = name.prefix { $0.isLetter || $0.isNumber }
        return word.prefix(1).uppercased() + word.dropFirst()
    }
}

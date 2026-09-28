import Foundation
import Testing
@testable import RepoRadar

private func run(_ id: Int, workflow: Int, created: String, status: String, conclusion: String?) -> String {
    """
    {"id": \(id), "name": "CI", "display_title": "t", "head_branch": "main", "event": "push",
     "status": "\(status)", "conclusion": \(conclusion.map { "\"\($0)\"" } ?? "null"),
     "workflow_id": \(workflow), "run_number": \(id), "html_url": "https://github.com/o/r/actions/runs/\(id)",
     "created_at": "\(created)", "updated_at": "\(created)", "run_started_at": null,
     "actor": {"login": "me"}, "repository": {"full_name": "o/r"}}
    """
}

@Test func latestPerWorkflowAndOverall() throws {
    let json = """
    {"total_count": 4, "workflow_runs": [
      \(run(1, workflow: 10, created: "2026-01-01T00:00:00Z", status: "completed", conclusion: "failure")),
      \(run(2, workflow: 10, created: "2026-01-02T00:00:00Z", status: "completed", conclusion: "success")),
      \(run(3, workflow: 20, created: "2026-01-03T00:00:00Z", status: "in_progress", conclusion: nil)),
      \(run(4, workflow: 30, created: "2026-01-01T00:00:00Z", status: "completed", conclusion: "timed_out"))
    ]}
    """
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .iso8601
    let runs = try decoder.decode(WorkflowRunsPage.self, from: Data(json.utf8)).workflowRuns

    let latest = runs.latestPerWorkflow()
    #expect(latest.map(\.id) == [3, 2, 4])          // newest per workflow; the old failure of 10 is superseded
    #expect(latest.map(\.state) == [.running, .success, .failure])
    #expect(latest.overall == .failure)
    #expect(Array(latest.prefix(2)).overall == .running)
    #expect([WorkflowRun]().overall == nil)
}

@Test func notificationLinksAndPullRequestRepo() throws {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .iso8601

    let json = """
    [{"id": "1", "unread": true, "reason": "review_requested", "updated_at": "2026-01-01T00:00:00Z",
      "subject": {"title": "Fix", "type": "PullRequest", "url": "https://api.github.com/repos/o/r/pulls/12"},
      "repository": {"full_name": "o/r"}},
     {"id": "2", "unread": false, "reason": "subscribed", "updated_at": "2026-01-01T00:00:00Z",
      "subject": {"title": "v1", "type": "Release", "url": "https://api.github.com/repos/o/r/releases/9"},
      "repository": {"full_name": "o/r"}}]
    """
    let items = try decoder.decode([GitHubNotification].self, from: Data(json.utf8))
    #expect(items[0].ref == IssueRef(repo: "o/r", number: 12, isPullRequest: true))
    #expect(items[0].webURL.absoluteString == "https://github.com/o/r/pull/12")
    #expect(items[0].reasonLabel == "Review requested")
    #expect(items[1].ref == nil)
    #expect(items[1].webURL.absoluteString == "https://github.com/o/r/releases")

    let pr = """
    {"id": 5, "number": 3, "title": "t", "html_url": "https://github.com/o/r/pull/3", "draft": null,
     "user": {"login": "me"}, "comments": 0, "created_at": "2026-01-01T00:00:00Z",
     "updated_at": "2026-01-01T00:00:00Z", "repository_url": "https://api.github.com/repos/o/r"}
    """
    #expect(try decoder.decode(PullRequest.self, from: Data(pr.utf8)).repo == "o/r")
}

@Test func markdownBlocks() {
    let blocks = MarkdownBlock.parse("""
    <!-- template -->
    ## Summary
    Line one
    line two.

    - **Price** binding
      wraps here
      - nested
    - [x] done
    1. first
    ```swift
    let x = 1
    ```
    > quoted
    | A | B |
    |---|---|
    | 1 | 2 |
    ---
    """)
    #expect(blocks == [
        .heading(level: 2, text: "Summary"),
        .paragraph("Line one line two."),
        .listItem(marker: "•", depth: 0, text: "**Price** binding wraps here"),
        .listItem(marker: "•", depth: 1, text: "nested"),
        .listItem(marker: "☑", depth: 0, text: "done"),
        .listItem(marker: "1.", depth: 0, text: "first"),
        .code("let x = 1"),
        .quote("quoted"),
        .table([["A", "B"], ["1", "2"]]),
        .rule,
    ])
}

@Test func workflowGraphFromNeeds() throws {
    let yaml = """
    name: deploy
    on: push   # comment
    jobs:
      ci:
        uses: ./.github/workflows/ci.yml
      images:
        needs: ci
        runs-on: ubuntu-latest
        steps:
          - run: echo "needs: not-a-key"
      weapp:
        needs: [ci]
        if: false
      deploy:
        name: "deploy"
        needs:
          - images
    """
    let declared = WorkflowYAML.jobs(in: yaml)
    #expect(declared == [
        DeclaredJob(id: "ci", name: nil, needs: []),
        DeclaredJob(id: "images", name: nil, needs: ["ci"]),
        DeclaredJob(id: "weapp", name: nil, needs: ["ci"]),
        DeclaredJob(id: "deploy", name: "deploy", needs: ["images"]),
    ])

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let jobs = try decoder.decode([WorkflowJob].self, from: Data("""
    [{"id": 1, "name": "ci / check", "status": "completed", "conclusion": "success"},
     {"id": 2, "name": "images", "status": "completed", "conclusion": "success"},
     {"id": 3, "name": "weapp", "status": "completed", "conclusion": "skipped"},
     {"id": 4, "name": "deploy", "status": "completed", "conclusion": "success"}]
    """.utf8))

    let graph = JobGraph(jobs: jobs, declared: declared)
    // images and weapp share ci upstream but not downstream (only images feeds deploy), so they stay apart.
    #expect(graph.nodes.map { [$0.column, $0.row, $0.jobs.count] } == [[0, 0, 1], [1, 0, 1], [1, 1, 1], [2, 0, 1]])
    #expect(Set(graph.edges) == [.init(from: 1, to: 2), .init(from: 1, to: 3), .init(from: 2, to: 4)])
    #expect(graph.columns == 3)
}

@Test func ciNotificationRunHint() throws {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .iso8601
    func item(_ title: String, _ type: String = "CheckSuite") throws -> GitHubNotification {
        try decoder.decode(GitHubNotification.self, from: Data("""
        {"id": "1", "unread": true, "reason": "ci_activity", "updated_at": "2026-01-01T00:00:00Z",
         "subject": {"title": "\(title)", "type": "\(type)", "url": null}, "repository": {"full_name": "o/r"}}
        """.utf8))
    }
    let hint = try item("Release workflow run failed for v1.0.0 branch").workflowRunHint
    #expect(hint?.workflow == "Release" && hint?.branch == "v1.0.0")
    let spaced = try item("Deploy production workflow run succeeded for feat/ghcr-cicd branch").workflowRunHint
    #expect(spaced?.workflow == "Deploy production" && spaced?.branch == "feat/ghcr-cicd")
    #expect(try item("Something else").workflowRunHint == nil)
    #expect(try item("CI workflow run failed for main branch", "Issue").workflowRunHint == nil)
}

private func decodeJobs(_ names: [String]) throws -> [WorkflowJob] {
    let json = names.enumerated().map { #"{"id": \#($0.offset + 1), "name": "\#($0.element)"}"# }.joined(separator: ",")
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode([WorkflowJob].self, from: Data("[\(json)]".utf8))
}

/// A typical check.yml, drawn like GitHub: the four parallel jobs share one box, and the direct
/// `changes → ci-required` edge is dropped because `changes` already reaches it through them.
@Test func graphGroupsParallelJobsAndDropsRedundantEdges() throws {
    let declared = WorkflowYAML.jobs(in: """
    jobs:
      changes:
        runs-on: ubuntu-latest
      checks:
        needs: changes
      database:
        needs: changes
      images:
        needs: changes
      browser:
        needs: changes
      ci-required:
        needs: [changes, checks, database, images, browser]
    """)
    let graph = JobGraph(jobs: try decodeJobs(["changes", "images", "checks", "database", "browser", "ci-required"]), declared: declared)
    #expect(graph.nodes.map { $0.jobs.map(\.name) } == [["changes"], ["images", "checks", "database", "browser"], ["ci-required"]])
    #expect(graph.edges == [.init(from: 1, to: 2), .init(from: 2, to: 6)])
}

/// `deploy` needs `lint` two columns back; that line must route around `build`, not through it.
@Test @MainActor func graphEdgesAvoidNodes() throws {
    let declared = WorkflowYAML.jobs(in: """
    jobs:
      setup:
        runs-on: ubuntu-latest
      lint:
        runs-on: ubuntu-latest
      build:
        needs: setup
      deploy:
        needs: [build, lint]
    """)
    let graph = JobGraph(jobs: try decodeJobs(["setup", "lint", "build", "deploy"]), declared: declared)
    let view = JobGraphView(graph: graph, title: "t.yml", trigger: "push", selection: .constant(nil))
    #expect(graph.edges.count == 3)

    for edge in graph.edges {
        let from = try #require(view.frame(of: edge.from)), to = try #require(view.frame(of: edge.to))
        let path = view.connector(from: from, fromY: try #require(view.anchorY(of: edge.from)),
                                  to: to, toY: try #require(view.anchorY(of: edge.to)))
        var points: [CGPoint] = []
        path.forEach { element in
            switch element {
            case .move(let p), .line(let p): points.append(p)
            case .quadCurve(let p, _), .curve(let p, _, _): points.append(p)
            case .closeSubpath: break
            }
        }
        for (a, b) in zip(points, points.dropFirst()) {
            for step in 0...20 {
                let t = CGFloat(step) / 20
                let sample = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                for node in graph.nodes {
                    let rect = try #require(view.frame(of: node.id)).insetBy(dx: 2, dy: 2)
                    #expect(!rect.contains(sample), "edge \(edge.from)→\(edge.to) crosses \(node.jobs[0].name) at \(sample)")
                }
            }
        }
    }
}

@Test func graphFitScalesAndCenters() {
    // A wide graph in a small pane shrinks to the limiting width, centered vertically.
    let wide = JobGraphView.fitted(content: CGSize(width: 1000, height: 200), in: CGSize(width: 532, height: 400))
    #expect(abs(wide.scale - 0.5) < 0.001)
    #expect(abs(wide.offset.width - 16) < 0.001 && abs(wide.offset.height - 150) < 0.001)
    // A small graph grows, but never past 150%, and stays centered.
    let small = JobGraphView.fitted(content: CGSize(width: 100, height: 50), in: CGSize(width: 800, height: 600))
    #expect(small.scale == 1.5)
    #expect(small.offset == CGSize(width: 325, height: 262.5))
}

@Test func zoomKeepsPointUnderCursor() {
    let anchor = CGPoint(x: 300, y: 120)
    let offset = CGSize(width: 40, height: 20)
    let zoomed = JobGraphView.zoomedOffset(offset: offset, scale: 1, newScale: 2, anchor: anchor)
    // The graph point under the cursor before (260, 100) must still be under it after zooming.
    #expect(zoomed.width + 260 * 2 == anchor.x && zoomed.height + 100 * 2 == anchor.y)
}

import Foundation
import SwiftUI
import Testing
@testable import RepoRadar

private let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}()

private func run(_ id: Int, workflow: Int, branch: String = "main", status: String = "completed", conclusion: String? = "success",
                 day: Int, repo: String = "o/r") throws -> WorkflowRun {
    try decoder.decode(WorkflowRun.self, from: Data("""
    {"id": \(id), "name": "W\(workflow)", "display_title": "t", "head_branch": "\(branch)", "event": "push", "status": "\(status)",
     "conclusion": \(conclusion.map { "\"\($0)\"" } ?? "null"), "workflow_id": \(workflow), "run_number": \(id),
     "html_url": "https://github.com/\(repo)/actions/runs/\(id)", "created_at": "2026-10-\(String(format: "%02d", day))T00:00:00Z",
     "updated_at": "2026-10-\(String(format: "%02d", day))T00:00:00Z", "run_started_at": null,
     "actor": {"login": "me"}, "repository": {"full_name": "\(repo)"}}
    """.utf8))
}

@Test func workflowGroupsAndFilters() throws {
    let runs = [
        // W1: default branch failed, a newer feature run passed → needs attention, opens the failure.
        try run(1, workflow: 1, conclusion: "failure", day: 1), try run(2, workflow: 1, branch: "feat", day: 2),
        // W2: running now.
        try run(3, workflow: 2, day: 1), try run(4, workflow: 2, status: "in_progress", conclusion: nil, day: 3),
        // W3: waiting for a deployment review.
        try run(5, workflow: 3, status: "waiting", conclusion: nil, day: 4),
        // W4: passing.
        try run(6, workflow: 4, day: 5),
    ]
    let summaries = Workflows.summaries(["o/r": runs], defaultBranches: ["o/r": "main"])
    #expect(summaries.map(\.workflowId) == [3, 1, 2, 4])  // attention (newest first), running, passing
    #expect(summaries.map(\.group) == [.attention, .attention, .running, .passing])
    let w1 = try #require(summaries.first { $0.workflowId == 1 })
    #expect(w1.latest.id == 2 && w1.primaryRun.id == 1)
    #expect(summaries.filter(RunFilter.failing.matches).map(\.workflowId) == [1])
    #expect(summaries.filter(RunFilter.running.matches).map(\.workflowId) == [2])
    #expect(summaries.filter(RunFilter.waiting.matches).map(\.workflowId) == [3])
}

private let sampleLog = """
2026-10-25T10:00:00.1000000Z ##[group]Run actions/checkout@v4
2026-10-25T10:00:00.2000000Z with: repo
2026-10-25T10:00:01.0000000Z ##[endgroup]
2026-10-25T10:00:05.0000000Z [command]/usr/bin/swift test
2026-10-25T10:00:06.0000000Z Test Suite 'All' started
2026-10-25T10:00:07.0000000Z \u{1B}[32m✓\u{1B}[0m testHeadings
2026-10-25T10:00:08.0000000Z ✕ testNestedListIndent
2026-10-25T10:00:08.5000000Z ##[error]MarkdownTests.swift:88: XCTAssertEqual failed
2026-10-25T10:00:09.0000000Z ##[warning]Deprecated API
2026-10-25T10:00:10.0000000Z Executed 2 tests
"""

@Test func jobLogParsesMarkersTimestampsAndANSI() {
    let lines = JobLog.parse(sampleLog)
    #expect(lines.count == 9)  // the endgroup line is dropped
    #expect(lines[0] == LogLine(number: 1, text: "Run actions/checkout@v4", ansi: nil, kind: .group,
                                timestamp: ISO8601DateFormatter().date(from: "2026-10-25T10:00:00Z")))
    #expect(lines.map(\.kind) == [.group, .normal, .command, .normal, .normal, .normal, .error, .warning, .normal])
    #expect(lines[4].text == "✓ testHeadings" && lines[4].ansi != nil)
    #expect(lines.last?.number == 10)  // numbers follow the raw log
    #expect(ANSI.strip("\u{1B}[1;31mred\u{1B}[0m") == "red")
    #expect(String(ANSI.attributed("\u{1B}[31mred\u{1B}[0m plain").characters) == "red plain")
}

@Test func jobLogSplitsBySteps() throws {
    let steps = try decoder.decode([WorkflowJob.Step].self, from: Data("""
    [{"number": 1, "name": "Checkout", "status": "completed", "conclusion": "success",
      "started_at": "2026-10-25T10:00:00Z", "completed_at": "2026-10-25T10:00:04Z"},
     {"number": 2, "name": "Run swift test", "status": "completed", "conclusion": "failure",
      "started_at": "2026-10-25T10:00:05Z", "completed_at": "2026-10-25T10:00:10Z"},
     {"number": 3, "name": "Upload", "status": "completed", "conclusion": "skipped"}]
    """.utf8))
    let sections = JobLog.sections(JobLog.parse(sampleLog), steps: steps)
    #expect(sections.map(\.name) == ["Checkout", "Run swift test", "Upload"])
    #expect(sections.map(\.lines.count) == [2, 7, 0])
    #expect(sections.map(\.state) == [.success, .failure, .skipped])
    #expect(sections[1].errors == 1)
    // Without step times it's one section.
    #expect(JobLog.sections(JobLog.parse("plain\nlog"), steps: []).count == 1)
}

@Test func jobLogFoldsAroundErrors() {
    let raw = (1...20).map { $0 == 10 ? "##[error]boom" : "line \($0)" }.joined(separator: "\n")
    let lines = JobLog.parse(raw)
    let rows = JobLog.rows(lines)
    // Lines 8–12 show (the error and 2 either side); 1–7 and 13–20 fold.
    #expect(rows.map(\.id) == ["f1", "l8", "l9", "l10", "l11", "l12", "f13"])
    #expect(rows.first == .fold(first: 1, count: 7) && rows.last == .fold(first: 13, count: 8))
    #expect(JobLog.rows(lines, expanded: [1]).count == 7 + 5 + 1)
    // No errors: the tail shows.
    #expect(JobLog.rows(JobLog.parse((1...30).map { "l\($0)" }.joined(separator: "\n")), tail: 5).map(\.id) == ["f1", "l26", "l27", "l28", "l29", "l30"])
    #expect(JobLog.filter(lines, "BOOM").map(\.number) == [10])
}

@Test func jobFailuresPreferAnnotations() {
    let lines = JobLog.parse(sampleLog)
    let notes = [Annotation(path: "Tests/MarkdownTests.swift", startLine: 88, annotationLevel: "failure",
                            title: "", message: "MarkdownTests.swift:88: XCTAssertEqual failed\nmore"),
                 Annotation(path: nil, startLine: nil, annotationLevel: "warning", title: nil, message: "ignored")]
    let failures = JobLog.failures(annotations: notes, lines: lines)
    #expect(failures.count == 1)
    #expect(failures[0].place == ":88" && failures[0].line == 8)
    #expect(failures[0].title == "MarkdownTests.swift:88: XCTAssertEqual failed")  // an empty title falls back to the message
    // No annotations: the error lines themselves.
    #expect(JobLog.failures(annotations: [], lines: lines).map(\.line) == [8])
}

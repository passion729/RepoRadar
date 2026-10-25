import Foundation

// Pure rules behind the data visualizations (spec §5). No SwiftUI here, so the tests can pin them down.

// MARK: - Pull request readiness

/// Checks → Reviews → Branch → Merge; the first step that isn't done is what blocks the merge.
enum Readiness {
    struct Step: Hashable {
        enum Kind: CaseIterable { case checks, reviews, branch, merge }
        let kind: Kind
        let state: StatusKind
        let text: String
    }

    static func checkState(status: String?, conclusion: String?, state: String?) -> StatusKind {
        if let state {  // a commit status context
            switch state {
            case "SUCCESS": return .success
            case "FAILURE", "ERROR": return .failure
            default: return .running
            }
        }
        guard status == "COMPLETED" else { return status == "IN_PROGRESS" ? .running : .waiting }
        switch conclusion {
        case "SUCCESS", "NEUTRAL": return .success
        case "SKIPPED", "CANCELLED", "STALE": return .skipped
        default: return .failure
        }
    }

    static func steps(_ pull: PullSummary, youAreRequested: Bool = false) -> [Step] {
        let total = pull.checks.count(where: { $0.state != .skipped })
        let passed = pull.checks.count(where: { $0.state == .success })
        let failed = pull.checks.count(where: { $0.state == .failure })
        let running = pull.checks.count(where: { $0.state == .running || $0.state == .waiting })
        let checks: Step = if total == 0 {
            Step(kind: .checks, state: .success, text: "No checks")
        } else if failed > 0 {
            Step(kind: .checks, state: .failure, text: "Checks \(passed)/\(total) · \(failed) failing")
        } else if running > 0 {
            Step(kind: .checks, state: .running, text: "Checks \(passed)/\(total) · \(running) running")
        } else {
            Step(kind: .checks, state: .success, text: "Checks \(passed)/\(total)")
        }

        let approvals = pull.approvedBy.count
        let reviews: Step = switch pull.reviewDecision {
        case "CHANGES_REQUESTED":
            Step(kind: .reviews, state: .failure, text: "Changes requested by \(pull.changesRequestedBy.joined(separator: ", "))")
        case "APPROVED":
            Step(kind: .reviews, state: .success, text: "Approved by \(pull.approvedBy.joined(separator: ", "))")
        case nil where approvals > 0:
            Step(kind: .reviews, state: .success, text: "Approved by \(pull.approvedBy.joined(separator: ", "))")
        case nil:
            Step(kind: .reviews, state: .success, text: "No review required")
        default:
            Step(kind: .reviews, state: .waiting,
                 text: "Reviews \(approvals)/\(approvals + max(pull.pendingReviewers, 1))" + (youAreRequested ? " · you're next" : ""))
        }

        let branch: Step = if pull.mergeable == "CONFLICTING" || pull.mergeState == "DIRTY" {
            Step(kind: .branch, state: .failure, text: "Conflicts with \(pull.baseRef)")
        } else if pull.mergeState == "BEHIND" {
            Step(kind: .branch, state: .waiting, text: "Behind \(pull.baseRef)")
        } else if pull.mergeable == "UNKNOWN" {
            Step(kind: .branch, state: .running, text: "Checking for conflicts")
        } else {
            Step(kind: .branch, state: .success, text: "No conflicts")
        }

        let ready = [checks, reviews, branch].allSatisfy { $0.state == .success }
        let merge = Step(kind: .merge, state: ready ? .success : .skipped, text: ready ? "Ready to merge" : "Merge")
        return [checks, reviews, branch, merge]
    }

    /// Index of the step that blocks the merge, or nil when it's ready.
    static func blocker(_ steps: [Step]) -> Int? {
        steps.firstIndex { $0.state != .success && $0.kind != .merge }
    }
}

// MARK: - Run statistics

enum RunStats {
    /// Passed ÷ (passed + failed); running, queued, cancelled and skipped runs don't count. Nil without data.
    static func passRate(_ runs: [WorkflowRun]) -> Double? {
        let passed = runs.count { $0.state == .success }
        let failed = runs.count { $0.state == .failure }
        return passed + failed == 0 ? nil : Double(passed) / Double(passed + failed)
    }

    /// ≥ 90% green, 75–89% amber, under 75% red.
    static func tone(ofPassRate rate: Double) -> Tone {
        rate >= 0.9 ? .green : rate >= 0.75 ? .amber : .red
    }

    /// "Usually": the median duration of the workflow's last 10 successful runs.
    static func usualDuration(ofWorkflow id: Int, in runs: [WorkflowRun]) -> TimeInterval? {
        let durations = runs.filter { $0.workflowId == id && $0.state == .success }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(10)
            .map(\.duration)
            .sorted()
        guard !durations.isEmpty else { return nil }
        let middle = durations.count / 2
        return durations.count.isMultiple(of: 2) ? (durations[middle - 1] + durations[middle]) / 2 : durations[middle]
    }

    /// Time left by the usual duration; negative when the run is already slower than usual.
    static func remaining(elapsed: TimeInterval, usual: TimeInterval) -> TimeInterval { usual - elapsed }

    /// "about 5 min left" / "3 min slower than usual".
    static func remainingText(elapsed: TimeInterval, usual: TimeInterval) -> String {
        let left = remaining(elapsed: elapsed, usual: usual)
        let minutes = max(1, Int((abs(left) / 60).rounded()))
        return left >= 0 ? "about \(minutes) min left" : "\(minutes) min slower than usual"
    }

    /// "2:10".
    static func clock(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        return seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Log excerpts

enum LogExcerpt {
    struct Line: Hashable {
        let number: Int
        let text: String
        let isError: Bool
    }

    /// Lines with `##[error]` and `context` lines around each, merged where they overlap, at most `limit` groups.
    /// Timestamps and the `##[error]` marker are stripped.
    static func errors(in log: String, context: Int = 2, limit: Int = 3) -> [[Line]] {
        let lines = log.split(separator: "\n", omittingEmptySubsequences: false).map(clean)
        let hits = lines.indices.filter { lines[$0].isError }
        var groups: [ClosedRange<Int>] = []
        for hit in hits {
            let range = max(0, hit - context)...min(lines.count - 1, hit + context)
            if let last = groups.last, range.lowerBound <= last.upperBound + 1 {
                groups[groups.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                groups.append(range)
            }
        }
        return groups.prefix(limit).map { range in
            range.map { Line(number: $0 + 1, text: lines[$0].text, isError: lines[$0].isError) }
        }
    }

    private static func clean(_ raw: Substring) -> (text: String, isError: Bool) {
        var line = String(raw)
        // "2026-01-01T00:00:00.0000000Z " prefix on every Actions log line.
        if line.count > 29, line.dropFirst(10).first == "T", line.prefix(4).allSatisfy(\.isNumber),
           let space = line.firstIndex(of: " ") {
            line = String(line[line.index(after: space)...])
        }
        if line.hasPrefix("##[error]") { return (String(line.dropFirst(9)), true) }
        return (line, false)
    }
}

// MARK: - GitHub label colors

/// GitHub labels keep their repository color: the chip is that color at 22%, and the text is the same hue
/// darkened (light appearance) or lightened (dark appearance) until it reaches 4.5:1 on the window.
enum LabelColors {
    static func text(_ hex: UInt32, dark: Bool) -> UInt32 {
        let background: UInt32 = dark ? 0x1E1E22 : 0xFFFFFF
        let target: UInt32 = dark ? 0xFFFFFF : 0x000000
        var color = hex
        for step in 0...20 where contrast(color, background) < 4.5 {
            color = mix(hex, target, Double(step) / 20)
        }
        return color
    }

    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    static func luminance(_ hex: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let value = Double((hex >> shift) & 0xFF) / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    static func mix(_ a: UInt32, _ b: UInt32, _ amount: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let x = Double((a >> shift) & 0xFF), y = Double((b >> shift) & 0xFF)
            return UInt32((x + (y - x) * amount).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }
}

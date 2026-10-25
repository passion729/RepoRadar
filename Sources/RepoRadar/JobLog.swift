import SwiftUI

/// One line of an Actions job log.
struct LogLine: Hashable, Identifiable {
    enum Kind: Hashable { case normal, error, warning, group, command }

    /// 1-based, over the whole job log.
    let number: Int
    /// Without the timestamp, the `##[…]` marker and ANSI codes.
    let text: String
    /// The original text with its ANSI colors, when it had any.
    let ansi: String?
    let kind: Kind
    let timestamp: Date?

    var id: Int { number }
}

/// The log lines of one step (A8).
struct LogSection: Identifiable, Hashable {
    let id: Int
    let name: String
    let state: StatusKind
    let duration: TimeInterval?
    let lines: [LogLine]

    var errors: Int { lines.count { $0.kind == .error } }
}

enum JobLog {
    /// A row of the folded log: a line, or "┄ n lines" standing for a run of hidden ones.
    enum Row: Identifiable, Hashable {
        case line(LogLine)
        case fold(first: Int, count: Int)

        var id: String {
            switch self {
            case .line(let line): "l\(line.number)"
            case .fold(let first, _): "f\(first)"
            }
        }
    }

    // ponytail: whole log in memory (GitHub caps a job log well below what that can't hold); stream if it ever isn't.
    static func parse(_ raw: String) -> [LogLine] {
        var lines: [LogLine] = []
        var cachedPrefix = Substring()
        var cachedDate: Date?
        let formatter = ISO8601DateFormatter()
        for (index, rawLine) in raw.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            var line = rawLine.hasSuffix("\r") ? rawLine.dropLast() : rawLine
            var timestamp: Date?
            // "2026-01-01T00:00:00.1234567Z " on every line; parse the second once per second.
            if line.count > 20, line.dropFirst(10).first == "T", let space = line.firstIndex(of: " "), line[..<space].hasSuffix("Z") {
                let prefix = line.prefix(19)
                if prefix != cachedPrefix {
                    cachedPrefix = prefix
                    cachedDate = formatter.date(from: prefix + "Z")
                }
                timestamp = cachedDate
                line = line[line.index(after: space)...]
            }
            var kind = LogLine.Kind.normal
            for (marker, markerKind) in [("##[error]", LogLine.Kind.error), ("##[warning]", .warning), ("##[group]", .group), ("[command]", .command)]
            where line.hasPrefix(marker) {
                kind = markerKind
                line = line.dropFirst(marker.count)
                break
            }
            if line.hasPrefix("##[endgroup]") { continue }
            let text = String(line)
            let plain = ANSI.strip(text)
            lines.append(LogLine(number: index + 1, text: plain, ansi: plain == text ? nil : text, kind: kind, timestamp: timestamp))
        }
        return lines
    }

    /// Splits the log by step using the steps' start times; without times, it's one section.
    static func sections(_ lines: [LogLine], steps: [WorkflowJob.Step]) -> [LogSection] {
        let timed = steps.filter { $0.startedAt != nil }.sorted { $0.number < $1.number }
        guard !timed.isEmpty, lines.contains(where: { $0.timestamp != nil }) else {
            return [LogSection(id: 0, name: "Log", state: .skipped, duration: nil, lines: lines)]
        }
        var buckets = [[LogLine]](repeating: [], count: timed.count)
        var current = 0
        for line in lines {
            if let time = line.timestamp {
                // Step times are whole seconds; a line belongs to the last step started by then.
                while current + 1 < timed.count, let next = timed[current + 1].startedAt, next <= time { current += 1 }
            }
            buckets[current].append(line)
        }
        return steps.sorted { $0.number < $1.number }.map { step in
            let index = timed.firstIndex(of: step)
            let duration = step.startedAt.flatMap { start in step.completedAt.map { $0.timeIntervalSince(start) } }
            return LogSection(id: step.number, name: step.name, state: step.state.status, duration: duration,
                              lines: index.map { buckets[$0] } ?? [])
        }
    }

    /// Errors with `context` lines either side; everything else folds into "┄ n lines" rows unless expanded.
    /// With no error lines, the last `tail` lines show (where a failure usually explains itself).
    static func rows(_ lines: [LogLine], context: Int = 2, tail: Int = 12, expanded: Set<Int> = []) -> [Row] {
        guard !lines.isEmpty else { return [] }
        var keep = [Bool](repeating: false, count: lines.count)
        let errors = lines.indices.filter { lines[$0].kind == .error }
        if errors.isEmpty {
            for index in max(0, lines.count - tail)..<lines.count { keep[index] = true }
        } else {
            for index in errors {
                for near in max(0, index - context)...min(lines.count - 1, index + context) { keep[near] = true }
            }
        }
        var rows: [Row] = []
        var index = 0
        while index < lines.count {
            if keep[index] {
                rows.append(.line(lines[index]))
                index += 1
                continue
            }
            let start = index
            while index < lines.count, !keep[index] { index += 1 }
            let first = lines[start].number
            if expanded.contains(first) {
                rows += lines[start..<index].map(Row.line)
            } else {
                rows.append(.fold(first: first, count: index - start))
            }
        }
        return rows
    }

    /// One entry of the failure list (A7).
    struct Failure: Hashable {
        let title: String
        /// ":88" or "Tests.swift:88".
        let place: String?
        let detail: String?
        /// The log line it jumps to, when found.
        let line: Int?
    }

    /// Failures from the check run's annotations (failure level); without them, the log's `##[error]` lines.
    /// An annotation jumps to the first error line that quotes it.
    static func failures(annotations: [Annotation], lines: [LogLine]) -> [Failure] {
        let errors = lines.filter { $0.kind == .error }
        let notes = annotations.filter { $0.annotationLevel == "failure" }
        guard !notes.isEmpty else {
            return errors.prefix(50).map { Failure(title: String($0.text.prefix(80)), place: nil, detail: $0.text, line: $0.number) }
        }
        return notes.map { note in
            let firstLine = note.message.split(separator: "\n").first.map(String.init) ?? note.message
            let title = note.title.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            let needle = String((title ?? firstLine).prefix(40))
            let line = errors.first { $0.text.localizedCaseInsensitiveContains(needle) }
                ?? lines.first { $0.text.localizedCaseInsensitiveContains(needle) }
            let place = note.startLine.map { ":\($0)" }
            return Failure(title: title ?? String(firstLine.prefix(80)), place: place,
                           detail: [note.path.map { $0 + (place ?? "") }, note.message].compactMap { $0 }.joined(separator: "\n"),
                           line: line?.number)
        }
    }

    /// Lines matching a filter (case-insensitive), across the whole log.
    static func filter(_ lines: [LogLine], _ query: String) -> [LogLine] {
        query.isEmpty ? lines : lines.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }
}

// MARK: - ANSI colors

enum ANSI {
    private static let pattern = /\u{1B}\[[0-9;]*m/

    static func strip(_ text: String) -> String {
        text.contains("\u{1B}") ? text.replacing(pattern, with: "") : text
    }

    /// SGR colors and bold as an attributed string, for the dark log surface.
    static func attributed(_ text: String) -> AttributedString {
        var result = AttributedString()
        var color: Color?
        var bold = false
        var rest = Substring(text)
        while let match = rest.firstMatch(of: pattern) {
            append(rest[..<match.range.lowerBound], to: &result, color: color, bold: bold)
            let codes = match.output.dropFirst(2).dropLast().split(separator: ";").compactMap { Int($0) }
            for code in codes.isEmpty ? [0] : codes {
                switch code {
                case 0: color = nil; bold = false
                case 1: bold = true
                case 22: bold = false
                case 39: color = nil
                case 30...37: color = palette[code - 30]
                case 90...97: color = palette[code - 90 + 8]
                default: break
                }
            }
            rest = rest[match.range.upperBound...]
        }
        append(rest, to: &result, color: color, bold: bold)
        return result
    }

    private static func append(_ text: Substring, to result: inout AttributedString, color: Color?, bold: Bool) {
        guard !text.isEmpty else { return }
        var part = AttributedString(text)
        if let color { part.foregroundColor = color }
        if bold { part.inlinePresentationIntent = .stronglyEmphasized }
        result += part
    }

    /// Standard and bright colors, tuned for the dark log background.
    private static let palette: [Color] = [
        Color(hex: 0x6B6B73), Color(hex: 0xFF6B70), Color(hex: 0x62D590), Color(hex: 0xE8B04A),
        Color(hex: 0x6FB2FF), Color(hex: 0xBBA0FF), Color(hex: 0x5FD7E8), Color(hex: 0xD6D6DC),
        Color(hex: 0x8B8B94), Color(hex: 0xFF8F94), Color(hex: 0x7EE2A8), Color(hex: 0xF5C66B),
        Color(hex: 0x9CCBFF), Color(hex: 0xD2C0FF), Color(hex: 0x8FE6F0), Color.white,
    ]
}

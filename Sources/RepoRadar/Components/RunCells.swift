import SwiftUI

extension RunState {
    var status: StatusKind {
        switch self {
        case .success: .success
        case .failure: .failure
        case .running: .running
        case .queued: .waiting
        case .cancelled, .skipped: .skipped
        }
    }
}

extension TimeInterval {
    /// "3m 40s" style.
    var shortDuration: String {
        Duration.seconds(self).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow))
    }
}

/// A colored letter square standing in for a repository's avatar.
struct RepoSquare: View {
    let repo: String
    var size: CGFloat = 18

    private static let palette: [Color] = [Color(hex: 0x3A3A41), Tone.green.solid, Tone.purple.solid,
                                           Tone.red.solid, Tone.blue.solid, Color(hex: 0x6B6B73), Tone.amber.solid]

    /// Stable across launches (unlike `hashValue`), so a repository keeps its color.
    static func colorIndex(_ repo: String) -> Int {
        Int(repo.unicodeScalars.reduce(UInt32(0)) { $0 &* 31 &+ $1.value } % UInt32(palette.count))
    }

    var body: some View {
        let name = repo.split(separator: "/").last.map(String.init) ?? repo
        Text(name.prefix(1).uppercased())
            .font(.system(size: size * 0.55, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Self.palette[Self.colorIndex(repo)], in: .rect(cornerRadius: size * 0.28))
            .accessibilityHidden(true)
    }
}

/// Recent runs as a strip of cells, oldest on the left and the newest at the right edge (spec §5).
/// Missing runs are empty `fill.subtle` cells. With `onSelect`, each cell opens its run.
struct RunCells: View {
    /// Oldest first; only the last `count` are drawn.
    let runs: [WorkflowRun]
    let count: Int
    var cell = CGSize(width: 4, height: 12)
    var spacing: CGFloat = 2
    var onSelect: ((WorkflowRun) -> Void)?

    var body: some View {
        let shown = Array(runs.suffix(count))
        HStack(spacing: spacing) {
            ForEach(0..<(count - shown.count), id: \.self) { _ in
                RoundedRectangle(cornerRadius: radius).fill(Theme.Fill.subtle).frame(width: cell.width, height: cell.height)
            }
            ForEach(shown) { run in
                if let onSelect {
                    Button { onSelect(run) } label: { cellView(run) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Self.describe(run))
                } else {
                    cellView(run)
                }
            }
        }
        .modifier(SummaryLabel(enabled: onSelect == nil, label: Self.summary(shown)))
    }

    private var radius: CGFloat { min(3, cell.width / 3) }

    @ViewBuilder private func cellView(_ run: WorkflowRun) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        Group {
            switch run.state.status {
            case .waiting:
                shape.strokeBorder(StatusKind.waiting.color, style: StrokeStyle(lineWidth: cell.width < 6 ? 1 : 1.5, dash: [2, 1.5]))
            case .running:
                shape.fill(Color(hex: 0xF0A020))
            case let status:
                shape.fill(status.color)
            }
        }
        .frame(width: cell.width, height: cell.height)
        .contentShape(shape)
        .help(Self.describe(run))
    }

    static func describe(_ run: WorkflowRun) -> String {
        let sha = run.headSha.map { " · " + $0.prefix(7) } ?? ""
        return "Run #\(run.runNumber)\(sha) · \(run.state.label) · \(run.duration.shortDuration)"
    }

    /// "Last 6 runs: 5 succeeded, 1 failed".
    static func summary(_ runs: [WorkflowRun]) -> String {
        guard !runs.isEmpty else { return "No runs" }
        var counts: [StatusKind: Int] = [:]
        for run in runs { counts[run.state.status, default: 0] += 1 }
        let parts = StatusKind.allCases.compactMap { kind in counts[kind].map { "\($0) \(kind.label.lowercased())" } }
        return "Last \(runs.count) runs: " + parts.joined(separator: ", ")
    }
}

private struct SummaryLabel: ViewModifier {
    let enabled: Bool
    let label: String

    func body(content: Content) -> some View {
        if enabled {
            content.accessibilityElement(children: .ignore).accessibilityLabel(label)
        } else {
            content.accessibilityElement(children: .contain)
        }
    }
}

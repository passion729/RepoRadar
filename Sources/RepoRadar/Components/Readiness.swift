import SwiftUI

/// Checks → Reviews → Branch chips (spec §5). The step blocking the merge gets a stroke; long texts truncate.
struct ReadinessFlow: View {
    let steps: [Readiness.Step]

    var body: some View {
        let shown = steps.filter { $0.kind != .merge || $0.state == .success }
        let blocker = Readiness.blocker(steps)
        HStack(spacing: 6) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, step in
                if index > 0 {
                    Image(systemName: "arrow.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.Ink.tertiary)
                        .accessibilityHidden(true)
                }
                HStack(spacing: 4) {
                    if step.kind == .checks { StatusIcon(step.state, size: 10) }
                    Text(step.text).lineLimit(1).truncationMode(.tail)
                }
                .textStyle(.label)
                .foregroundStyle(tone(step.state).text)
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(tone(step.state).tint, in: .capsule)
                .overlay {
                    if blocker == steps.firstIndex(of: step) {
                        Capsule().strokeBorder(tone(step.state).solid.opacity(0.6), lineWidth: 1)
                    }
                }
                .layoutPriority(step.kind == .checks ? 1 : 0)
                .help(step.text)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(steps.map(\.text).joined(separator: ", "))
    }

    private func tone(_ state: StatusKind) -> Tone {
        switch state {
        case .success: .green
        case .failure: .red
        case .running, .waiting: .amber
        case .skipped: .neutral
        }
    }
}

/// "+312 −48 ▬ 9 files": green before red, at least 2 pt each.
struct ChangeBar: View {
    let additions: Int
    let deletions: Int
    var files: Int?
    /// The bar length for this change; the file list scales bars against its biggest file.
    var width: CGFloat = 80

    var body: some View {
        HStack(spacing: 8) {
            Text("+\(additions)").foregroundStyle(Tone.green.text)
            Text("−\(deletions)").foregroundStyle(Tone.red.text)
            HStack(spacing: 0) {
                let total = max(1, additions + deletions)
                Rectangle().fill(Tone.green.solid)
                    .frame(width: additions == 0 ? 0 : max(2, width * CGFloat(additions) / CGFloat(total)))
                Rectangle().fill(Tone.red.solid)
                    .frame(width: deletions == 0 ? 0 : max(2, width * CGFloat(deletions) / CGFloat(total)))
            }
            .frame(width: width, height: 6, alignment: .leading)
            .background(Theme.Fill.subtle)
            .clipShape(.capsule)
            if let files { Text("\(files) \(files == 1 ? "file" : "files")").foregroundStyle(Theme.Ink.secondary) }
        }
        .font(.system(size: 11.5, design: .monospaced).monospacedDigit())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(additions) additions, \(deletions) deletions" + (files.map { ", \($0) files" } ?? ""))
    }
}

/// One segment per job (6 pt high, 3 pt apart); over 12 jobs, a single bar filled by the share done.
struct JobProgress: View {
    let jobs: [WorkflowJob]

    var body: some View {
        Group {
            if jobs.count <= 12 {
                HStack(spacing: 3) {
                    ForEach(jobs) { job in Capsule().fill(color(job.state.status)).frame(height: 6) }
                }
            } else {
                let done = Double(jobs.count { !$0.state.isActive }) / Double(jobs.count)
                GeometryReader { proxy in
                    Capsule().fill(Theme.Fill.subtle)
                        .overlay(alignment: .leading) { Capsule().fill(Tone.green.solid).frame(width: proxy.size.width * done) }
                }
                .frame(height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(jobs.count { !$0.state.isActive }) of \(jobs.count) jobs done")
    }

    private func color(_ status: StatusKind) -> Color {
        switch status {
        case .success: Tone.green.solid
        case .failure: Tone.red.solid
        case .running: Color(hex: 0xF0A020)
        case .waiting: Theme.Fill.subtle
        case .skipped: Tone.neutral.solid
        }
    }
}

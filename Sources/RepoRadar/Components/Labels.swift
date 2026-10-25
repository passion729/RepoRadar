import SwiftUI

// Small labels (spec §4): count badges, chips, keyboard hints and status icons.

/// A count: 18 pt tall, at least 20 wide; over 99 shows "99+".
/// `.neutral` is gray with secondary text; other tones are solid with white text.
struct Badge: View {
    let count: Int
    var tone: Tone = .neutral

    static func text(_ count: Int) -> String { count > 99 ? "99+" : "\(count)" }

    var body: some View {
        Text(Self.text(count))
            .textStyle(.label)
            .foregroundStyle(tone == .neutral ? Theme.Ink.secondary : .white)
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 18)
            .background(tone == .neutral ? Theme.Selection.nav : tone.solid, in: .capsule)
            .fixedSize()
    }
}

/// A tinted capsule label such as "Review requested" or "Your push failed".
struct Chip: View {
    let text: String
    var tone: Tone = .neutral
    var systemImage: String?
    /// 18 pt instead of 20, for dense rows.
    var compact = false

    init(_ text: String, tone: Tone = .neutral, systemImage: String? = nil, compact: Bool = false) {
        self.text = text
        self.tone = tone
        self.systemImage = systemImage
        self.compact = compact
    }

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).imageScale(.small).accessibilityHidden(true)
            }
            Text(text)
        }
        .textStyle(.label)
        .lineLimit(1)
        .foregroundStyle(tone.text)
        .padding(.horizontal, 8)
        .frame(height: compact ? 18 : 20)
        .background(tone.tint, in: .capsule)
        .fixedSize()
    }
}

/// A GitHub label in its repository color (see `LabelColors`).
struct LabelChip: View {
    let label: IssueLabel

    var body: some View {
        let hex = UInt32(label.color, radix: 16) ?? 0x808080
        Text(label.name)
            .textStyle(.label)
            .lineLimit(1)
            .foregroundStyle(Color.dynamic(light: Color(hex: LabelColors.text(hex, dark: false)),
                                           dark: Color(hex: LabelColors.text(hex, dark: true))))
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Color(hex: hex, alpha: 0.22), in: .capsule)
            .fixedSize()
    }
}

/// A keyboard shortcut hint, e.g. ⌘K. Drawn relative to the surrounding text color,
/// so it reads on plain backgrounds and inside filled buttons alike.
struct Kbd: View {
    let keys: String

    init(_ keys: String) { self.keys = keys }

    var body: some View {
        Text(keys)
            .textStyle(.kbd)
            .opacity(0.72)
            .padding(.horizontal, 4)
            .frame(minWidth: 18, minHeight: 18)
            .background(.foreground.opacity(0.1), in: .rect(cornerRadius: Theme.Radius.kbd))
            .fixedSize()
            .accessibilityLabel("Shortcut \(keys)")
    }
}

// MARK: - Status

/// The five states every run, job, check and step is drawn in.
enum StatusKind: CaseIterable {
    case success, failure, running, waiting, skipped

    var tone: Tone {
        switch self {
        case .success: .green
        case .failure: .red
        case .running, .waiting: .amber
        case .skipped: .neutral
        }
    }

    /// Icon color; waiting is a darker amber than running.
    var color: Color { self == .waiting ? Color(hex: 0xC27A00) : tone.solid }

    var label: String {
        switch self {
        case .success: "Succeeded"
        case .failure: "Failed"
        case .running: "Running"
        case .waiting: "Waiting"
        case .skipped: "Skipped"
        }
    }

    var symbol: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .failure: "xmark.circle.fill"
        case .running: "circle"  // drawn as a spinning ring instead
        case .waiting: "circle.dashed"
        case .skipped: "minus.circle.fill"
        }
    }
}

/// A status in one of three sizes (14 / 12 / 10). Shapes differ per state, not only colors.
/// Running spins once a second, and holds still with Reduce Motion.
struct StatusIcon: View {
    let kind: StatusKind
    var size: CGFloat = 14

    init(_ kind: StatusKind, size: CGFloat = 14) {
        self.kind = kind
        self.size = size
    }

    var body: some View {
        Group {
            if kind == .running {
                SpinningRing(color: kind.color, lineWidth: max(1.5, size * 0.16))
                    .padding(size * 0.09)  // match the inset of the SF circle symbols
            } else {
                Image(systemName: kind.symbol)
                    .font(.system(size: size, weight: kind == .waiting ? .bold : .regular))
                    .foregroundStyle(kind.color)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(kind.label)
    }
}

private struct SpinningRing: View {
    let color: Color
    let lineWidth: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(spinning && !reduceMotion ? 360 : 0))
                .animation(reduceMotion ? nil : .linear(duration: 1).repeatForever(autoreverses: false), value: spinning)
        }
        .onAppear { spinning = true }
    }
}

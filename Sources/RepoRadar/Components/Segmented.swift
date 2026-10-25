import SwiftUI

/// One option of a `Segmented` control. A count is always shown when given, even 0.
struct Segment<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var count: Int?
    /// A 10 pt status icon before the title, for filters like "Failing".
    var status: StatusKind?

    var id: Value { value }
}

/// Filter tabs on a `fill.subtle` track; the selected segment is a raised capsule.
struct Segmented<Value: Hashable>: View {
    @Binding var selection: Value
    let segments: [Segment<Value>]
    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(segments) { segment in
                let isSelected = segment.value == selection
                Button { selection = segment.value } label: {
                    HStack(spacing: 5) {
                        if let status = segment.status { StatusIcon(status, size: 10) }
                        Text(segment.title).foregroundStyle(isSelected ? Theme.Ink.primary : Theme.Ink.secondary)
                        if let count = segment.count {
                            Text(Badge.text(count)).foregroundStyle(Theme.Ink.tertiary)
                        }
                    }
                    .textStyle(.button)
                    .fontWeight(isSelected ? .semibold : .medium)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(Theme.Surface.raised)
                                .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
                                .matchedGeometryEffect(id: "selection", in: namespace)
                        }
                    }
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(segment.count.map { "\(segment.title), \($0)" } ?? segment.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Theme.Fill.subtle, in: .capsule)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: selection)
        .fixedSize()
    }
}

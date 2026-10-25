import SwiftUI

/// Two content panes split by a 1 pt separator (spec §3): one keeps a stored size the user can drag,
/// the other takes the rest. No margins, corners or shadows.
struct SplitPane<First: View, Second: View>: View {
    enum Sized { case first, second }

    var axis: Axis = .horizontal
    /// Which pane has the stored size.
    var sized: Sized = .first
    @Binding var size: Double
    let range: ClosedRange<CGFloat>
    /// The flexible pane never gets smaller than this.
    var minFlexible: CGFloat = 0
    @ViewBuilder let first: First
    @ViewBuilder let second: Second
    @State private var dragStart: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            let total = axis == .horizontal ? proxy.size.width : proxy.size.height
            let fixed = clamp(CGFloat(size), total: total)
            let layout = axis == .horizontal ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            layout {
                pane(first, length: sized == .first ? fixed : nil)
                separator(total: total)
                pane(second, length: sized == .second ? fixed : nil)
            }
        }
    }

    private func clamp(_ value: CGFloat, total: CGFloat) -> CGFloat {
        max(range.lowerBound, min(value, range.upperBound, total - minFlexible - 1))
    }

    /// Panes clip at their top-left, so oversized content (a wide graph) can't recenter them.
    private func pane(_ content: some View, length: CGFloat?) -> some View {
        content
            .frame(width: axis == .horizontal ? length : nil, height: axis == .vertical ? length : nil, alignment: .topLeading)
            .frame(minWidth: 0, maxWidth: axis == .horizontal && length != nil ? nil : .infinity,
                   minHeight: 0, maxHeight: axis == .vertical && length != nil ? nil : .infinity, alignment: .topLeading)
            .clipped()
    }

    private func separator(total: CGFloat) -> some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(width: axis == .horizontal ? 1 : nil, height: axis == .vertical ? 1 : nil)
            .overlay {
                // A wider invisible strip makes the hairline easy to grab.
                Color.clear
                    .frame(width: axis == .horizontal ? 8 : nil, height: axis == .vertical ? 8 : nil)
                    .contentShape(.rect)
                    .pointerStyle(axis == .horizontal ? .columnResize : .rowResize)
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { drag in
                            let start = dragStart ?? clamp(CGFloat(size), total: total)
                            dragStart = start
                            let delta = axis == .horizontal ? drag.translation.width : drag.translation.height
                            size = Double(clamp(sized == .first ? start + delta : start - delta, total: total))
                        }
                        .onEnded { _ in dragStart = nil })
            }
            .zIndex(1)
            .accessibilityHidden(true)
    }
}

/// Placeholder rows for a first load (spec §8): six gray rows instead of a spinner.
struct SkeletonRows: View {
    var count = 6
    var rowHeight: CGFloat = 54

    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { index in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 10).fill(Theme.Fill.subtle).frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule().fill(Theme.Fill.subtle).frame(width: index.isMultiple(of: 2) ? 260 : 200, height: 10)
                        Capsule().fill(Theme.Fill.subtle).frame(width: 150, height: 8)
                    }
                    Spacer()
                }
                .padding(.horizontal, Theme.Space.rowPadding)
                .frame(height: rowHeight)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }
}

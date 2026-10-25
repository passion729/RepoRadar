import SwiftUI

/// The job dependency graph (A5, spec §5): columns by `needs` level with a title each, 138 × 42 nodes, elbow
/// connectors through the gaps. Edges into a failed job are red, into a skipped job dashed; failed nodes get a
/// red ring. Zoom 50–200% with the floating control, ⌘= / ⌘−, or a pinch; Fit sizes it to the pane.
struct JobGraphView: View {
    let graph: JobGraph
    @Binding var selection: WorkflowJob.ID?
    /// Expands a collapsed matrix node.
    var expand: (String) -> Void = { _ in }
    @State private var scale: CGFloat = 1
    @State private var pinchStart: CGFloat?
    @State private var container: CGSize = .zero

    static let zoomRange: ClosedRange<CGFloat> = 0.5...2

    // Every metric is its 100% value times `scale`, so zooming re-lays out sharp text instead of stretching it.
    private var nodeSize: CGSize { CGSize(width: 138 * scale, height: 42 * scale) }
    private var rowGap: CGFloat { 10 * scale }
    private var headerHeight: CGFloat { 22 * scale }
    private let inset: CGFloat = 16

    /// At least 24, growing to fill the pane (up to 96) so a short graph spreads out.
    private var columnGap: CGFloat {
        let columns = CGFloat(graph.columns)
        guard columns > 1 else { return 24 * scale }
        let free = (container.width - inset * 2 - columns * nodeSize.width) / (columns - 1)
        return min(96 * scale, max(24 * scale, free))
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                ForEach(0..<graph.columns, id: \.self) { column in
                    Text(columnTitle(column))
                        .font(.system(size: 11 * scale, weight: .semibold))
                        .foregroundStyle(Theme.Ink.tertiary)
                        .lineLimit(1)
                        .frame(width: nodeSize.width, alignment: .leading)
                        .offset(x: x(of: column))
                }
                Canvas { context, _ in
                    for edge in graph.edges {
                        guard let from = frames[edge.from], let to = frames[edge.to],
                              let target = graph.nodes.first(where: { $0.id == edge.to }) else { continue }
                        let path = connector(from: from, fromY: from.midY, to: to, toY: to.midY)
                        let color: Color = target.state == .failure ? Tone.red.solid : Theme.Ink.tertiary.opacity(0.7)
                        let dash: [CGFloat] = target.state == .skipped ? [4 * scale, 3 * scale] : []
                        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.25 * scale, lineCap: .round, dash: dash))
                    }
                }
                .frame(width: canvasSize.width, height: canvasSize.height)
                .accessibilityHidden(true)
                ForEach(graph.nodes) { node in
                    let rect = frames[node.id]!
                    GraphNode(node: node, isSelected: node.jobs.contains { $0.id == selection }, scale: scale) {
                        if node.isGroup, let matrix = node.matrix { expand(matrix) } else { selection = node.id }
                    }
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
            .padding(inset)
            // Centred while it fits; scrolls once it doesn't.
            .frame(minWidth: container.width, minHeight: container.height)
        }
        .scrollIndicators(.automatic)
        .onGeometryChange(for: CGSize.self, of: \.size) { container = $0 }
        .overlay(alignment: .topLeading) { zoomControl.padding(10) }
        .gesture(MagnifyGesture()
            .onChanged { value in
                let start = pinchStart ?? scale
                pinchStart = start
                scale = clamp(start * value.magnification)
            }
            .onEnded { _ in pinchStart = nil })
    }

    /// − / percentage / + and Fit on a glass capsule, floating over the graph.
    private var zoomControl: some View {
        HStack(spacing: 2) {
            Button("Zoom Out", systemImage: "minus") { zoom(by: 1 / 1.25) }
                .keyboardShortcut("-")
                .disabled(scale <= Self.zoomRange.lowerBound)
            Text("\(Int((scale * 100).rounded()))%")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .frame(minWidth: 38)
            Button("Zoom In", systemImage: "plus") { zoom(by: 1.25) }
                .keyboardShortcut("=")
                .disabled(scale >= Self.zoomRange.upperBound)
            Divider().frame(height: 14)
            Button("Fit") { fit() }
                .labelStyle(.titleOnly)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 6)
                .help("Fit the graph to the pane")
        }
        .buttonStyle(IconButtonStyle(diameter: 24))
        .labelStyle(.iconOnly)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .glassEffect(.regular, in: .capsule)
    }

    private func zoom(by factor: CGFloat) {
        withAnimation(.snappy) { scale = clamp(scale * factor) }
    }

    private func fit() {
        let natural = CGSize(width: canvasSize.width / scale + inset * 2, height: canvasSize.height / scale + inset * 2)
        withAnimation(.snappy) { scale = Self.fitScale(content: natural, in: container) }
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }

    /// The zoom that fits `content` (at 100%) inside `container`, within 50–200%.
    static func fitScale(content: CGSize, in container: CGSize) -> CGFloat {
        guard content.width > 0, content.height > 0, container.width > 0, container.height > 0 else { return 1 }
        let scale = min(container.width / content.width, container.height / content.height)
        return min(max(scale, zoomRange.lowerBound), zoomRange.upperBound)
    }

    // MARK: Layout

    private func x(of column: Int) -> CGFloat { CGFloat(column) * (nodeSize.width + columnGap) }

    private var frames: [JobGraph.Node.ID: CGRect] {
        Dictionary(uniqueKeysWithValues: graph.nodes.map { node in
            (node.id, CGRect(x: x(of: node.column), y: headerHeight + CGFloat(node.row) * (nodeSize.height + rowGap),
                             width: nodeSize.width, height: nodeSize.height))
        })
    }

    private var canvasSize: CGSize {
        CGSize(width: max(nodeSize.width, x(of: max(graph.columns - 1, 0)) + nodeSize.width),
               height: (frames.values.map(\.maxY).max() ?? headerHeight) + rowGap)
    }

    private func columnTitle(_ column: Int) -> String {
        JobGraph.columnTitle(graph.nodes.filter { $0.column == column }.map(\.title), level: column)
    }

    func frame(of id: JobGraph.Node.ID) -> CGRect? { frames[id] }

    func anchorY(of id: JobGraph.Node.ID) -> CGFloat? { frames[id]?.midY }

    /// Edges only run through the gaps between columns and rows, never across a node: adjacent columns get one
    /// elbow at the middle of the gap; longer edges drop into a row gap, cross the skipped columns there, and come
    /// back up (or down) in the gap before the target.
    func connector(from: CGRect, fromY: CGFloat, to: CGRect, toY: CGFloat) -> Path {
        let start = CGPoint(x: from.maxX, y: fromY)
        let end = CGPoint(x: to.minX, y: toY)
        let exitX = start.x + columnGap / 2
        let enterX = end.x - columnGap / 2

        var points = [start]
        if enterX - exitX < 1 {  // neighbouring columns
            points += [CGPoint(x: exitX, y: start.y), CGPoint(x: exitX, y: end.y)]
        } else {
            let lane: CGFloat = if to.minY > from.minY {
                to.minY - rowGap / 2
            } else if to.minY < from.minY {
                from.minY - rowGap / 2
            } else {
                from.maxY + rowGap / 2
            }
            points += [CGPoint(x: exitX, y: start.y), CGPoint(x: exitX, y: lane),
                       CGPoint(x: enterX, y: lane), CGPoint(x: enterX, y: end.y)]
        }
        points.append(end)
        return roundedPolyline(points)
    }

    private func roundedPolyline(_ raw: [CGPoint]) -> Path {
        let points = raw.enumerated().filter { index, point in
            index == 0 || hypot(point.x - raw[index - 1].x, point.y - raw[index - 1].y) > 0.5
        }.map(\.element)
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for index in points.indices.dropFirst().dropLast() {
            let (previous, corner, next) = (points[index - 1], points[index], points[index + 1])
            let room = min(hypot(corner.x - previous.x, corner.y - previous.y), hypot(next.x - corner.x, next.y - corner.y)) / 2
            path.addArc(tangent1End: corner, tangent2End: next, radius: min(8 * scale, room))
        }
        path.addLine(to: points.last!)
        return path
    }
}

/// A job (or a collapsed matrix): status, name and duration on a raised card.
private struct GraphNode: View {
    let node: JobGraph.Node
    let isSelected: Bool
    let scale: CGFloat
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        let failed = node.state == .failure
        Button(action: action) {
            HStack(spacing: 8 * scale) {
                StatusIcon(node.state.status, size: 14 * scale)
                VStack(alignment: .leading, spacing: 1 * scale) {
                    Text(node.title)
                        .font(.system(size: 11.5 * scale, weight: .medium))
                        .foregroundStyle(Theme.Ink.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(detail)
                        .font(.system(size: 10.5 * scale).monospacedDigit())
                        .foregroundStyle(failed ? Tone.red.text : Theme.Ink.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10 * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isHovered ? Theme.Fill.hover : .clear, in: .rect(cornerRadius: Theme.Radius.node * scale))
            .background(Theme.Surface.raised, in: .rect(cornerRadius: Theme.Radius.node * scale))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.node * scale)
                    .strokeBorder(isSelected ? Theme.accent : failed ? Tone.red.solid : Theme.separator,
                                  lineWidth: (isSelected ? 2 : failed ? 1.5 : 1) * max(1, scale))
            }
            .background {
                if failed {  // 3 pt outer ring
                    RoundedRectangle(cornerRadius: (Theme.Radius.node + 3) * scale)
                        .inset(by: -3 * scale)
                        .fill(Tone.red.solid.opacity(0.15))
                }
            }
            .contentShape(.rect(cornerRadius: Theme.Radius.node * scale))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu {
            if let url = node.jobs[0].htmlUrl { LinkActions(urls: [url]) }
        }
        .help(node.isGroup ? "\(node.title): click to show each job" : "\(node.title) — \(node.state.label)")
        .accessibilityLabel("\(node.title), \(node.state.label), \(detail)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var detail: String {
        if node.isGroup {
            let failed = node.jobs.count { $0.state == .failure }
            let passed = node.jobs.count { $0.state == .success }
            return failed > 0 ? "\(passed) passed · \(failed) failed" : "\(passed) of \(node.jobs.count) passed"
        }
        let job = node.jobs[0]
        if job.state == .skipped { return "skipped" }
        if job.state == .queued { return "queued" }
        return job.duration.map { RunStats.clock($0) } ?? job.state.label.lowercased()
    }
}

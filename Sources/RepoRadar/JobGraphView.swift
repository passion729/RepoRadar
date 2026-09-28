import SwiftUI

/// GitHub-style workflow graph: jobs in dependency columns, joined by elbow connectors.
struct JobGraphView: View {
    let graph: JobGraph
    let title: String
    let trigger: String
    @Binding var selection: WorkflowJob.ID?
    /// Free pan offset of the graph; the canvas is unbounded, like GitHub's.
    @State private var offset: CGSize = .zero
    @State private var scale: CGFloat = 1
    @State private var dragStart: CGSize?
    @State private var isHovering = false
    @State private var scrollMonitor: Any?
    @State private var magnifyMonitor: Any?
    /// Pointer position in the pane, so zooming keeps the point under it fixed.
    @State private var pointer: CGPoint?
    @State private var contentSize: CGSize = .zero
    @State private var containerSize: CGSize = .zero
    /// How much of the graph must stay inside the pane, so it can never be panned out of sight.
    private let keepVisible: CGFloat = 80

    @Environment(\.fontTheme) private var fontTheme

    // Zoom re-lays out the graph at the new size (instead of scaleEffect, which stretches a bitmap and blurs),
    // so every metric is its 100% value times `scale`.
    private var nodeSize: CGSize { CGSize(width: 200 * scale, height: 40 * scale) }
    /// Row height and vertical padding inside a grouped box.
    private var groupRow: CGFloat { 28 * scale }
    private var groupPadding: CGFloat { 6 * scale }  // 6 + 28/2 = 20: first row level with a single box's center
    private var columnGap: CGFloat { 56 * scale }
    private var rowGap: CGFloat { 16 * scale }
    private var inset: CGFloat { 20 * scale }

    var body: some View {
        VStack(alignment: .leading, spacing: 16 * scale) {
            VStack(alignment: .leading, spacing: 2 * scale) {
                Text(title).themeFont(.title3, weight: .semibold)
                Text("on: \(trigger)").foregroundStyle(.secondary)
            }
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for edge in graph.edges {
                        guard let (from, to) = endpoints(edge) else { continue }
                        context.stroke(connector(from: from.rect, fromY: from.y, to: to.rect, toY: to.y),
                                       with: .style(.tertiary), lineWidth: 1.5 * scale)
                    }
                }
                .frame(width: canvasSize.width, height: canvasSize.height)
                .accessibilityHidden(true)

                ForEach(graph.nodes) { node in
                    let rect = frames[node.id]!
                    Group {
                        if node.isGroup {
                            JobGroupNode(jobs: node.jobs, rowHeight: groupRow, padding: groupPadding, selection: $selection)
                        } else {
                            JobNode(job: node.jobs[0], isSelected: selection == node.id) { selection = node.id }
                        }
                    }
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                }

                // Connection dots on top of the boxes, where the lines attach.
                Canvas { context, _ in
                    for edge in graph.edges {
                        guard let (from, to) = endpoints(edge) else { continue }
                        for point in [CGPoint(x: from.rect.maxX, y: from.y), CGPoint(x: to.rect.minX, y: to.y)] {
                            let (outer, inner) = (4 * scale, 3 * scale)
                            let dot = Path(ellipseIn: CGRect(x: point.x - outer, y: point.y - outer, width: outer * 2, height: outer * 2))
                            context.fill(dot, with: .color(Color(nsColor: .windowBackgroundColor)))
                            context.fill(Path(ellipseIn: CGRect(x: point.x - inner, y: point.y - inner, width: inner * 2, height: inner * 2)),
                                         with: .style(.secondary))
                        }
                    }
                }
                .frame(width: canvasSize.width, height: canvasSize.height)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        }
        .padding(inset)
        .environment(\.fontTheme, { var theme = fontTheme; theme.zoom = scale; return theme }())
        .fixedSize()
        .onGeometryChange(for: CGSize.self, of: \.size) { contentSize = $0 }  // at the current zoom
        .offset(offset)
        // Min 0: the graph clips and pans, so it must not force its full size onto the pane (that pushed headers away).
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGSize.self, of: \.size) { size in
            containerSize = size
            offset = clamped(offset)  // shrinking the pane must not strand the graph outside it
        }
        .clipped()
        .contentShape(.rect)  // empty space is grabbable too
        .gesture(pan)
        .onTapGesture(count: 2) {  // double-click resets to 100% at the top-left
            withAnimation(.smooth) {
                scale = 1
                offset = .zero
            }
        }
        .overlay(alignment: .topTrailing) {
            Button("Fit", systemImage: "arrow.up.left.and.arrow.down.right") { fit() }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help("Fit the graph to the pane and center it")
                .padding(10)
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                isHovering = true
                pointer = location
            case .ended:
                isHovering = false
                pointer = nil
            }
        }
        .onAppear(perform: installScrollMonitor)
        .onDisappear {
            scrollMonitor.map(NSEvent.removeMonitor)
            magnifyMonitor.map(NSEvent.removeMonitor)
            scrollMonitor = nil
            magnifyMonitor = nil
        }
        .help("Drag or two-finger scroll to pan · mouse wheel or pinch to zoom · double-click to reset")
    }

    // Drag anywhere to pan. The small minimum distance leaves plain clicks to the job nodes.
    private var pan: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { drag in
                let start = dragStart ?? offset
                dragStart = start
                offset = clamped(CGSize(width: start.width + drag.translation.width, height: start.height + drag.translation.height))
            }
            .onEnded { _ in dragStart = nil }
    }

    private func fit() {
        guard contentSize != .zero, containerSize != .zero else { return }
        let unscaled = CGSize(width: contentSize.width / scale, height: contentSize.height / scale)
        let placement = Self.fitted(content: unscaled, in: containerSize)
        withAnimation(.smooth) {
            scale = placement.scale
            offset = placement.offset
        }
    }

    /// Scale that fits `content` inside `container` (with a margin, at most 150%) and the offset that centers it.
    static func fitted(content: CGSize, in container: CGSize, margin: CGFloat = 16) -> (scale: CGFloat, offset: CGSize) {
        let scale = min(1.5, max(0.1, min((container.width - margin * 2) / content.width,
                                          (container.height - margin * 2) / content.height)))
        return (scale, CGSize(width: (container.width - content.width * scale) / 2,
                              height: (container.height - content.height * scale) / 2))
    }

    /// Keeps at least `keepVisible` points of the graph (or all of it, if smaller) inside the pane.
    private func clamped(_ proposed: CGSize, scale: CGFloat? = nil) -> CGSize {
        let scale = scale ?? self.scale
        func limit(_ value: CGFloat, content: CGFloat, container: CGFloat) -> CGFloat {
            let margin = min(keepVisible, content)
            return min(max(value, margin - content), container - margin)
        }
        guard contentSize != .zero, containerSize != .zero else { return proposed }
        // contentSize is measured at the current zoom; rescale it when checking a new zoom level.
        let ratio = scale / self.scale
        return CGSize(width: limit(proposed.width, content: contentSize.width * ratio, container: containerSize.width),
                      height: limit(proposed.height, content: contentSize.height * ratio, container: containerSize.height))
    }

    /// Trackpad: two-finger scroll pans, pinch zooms. Mouse: the wheel zooms around the pointer.
    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard isHovering else { return event }
            if event.hasPreciseScrollingDeltas {  // trackpad or Magic Mouse surface: pan
                offset = clamped(CGSize(width: offset.width + event.scrollingDeltaX,
                                        height: offset.height + event.scrollingDeltaY))
            } else {  // wheel notches: zoom, ~10% per notch
                zoom(by: pow(1.1, event.scrollingDeltaY))
            }
            return nil
        }
        magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { event in
            guard isHovering else { return event }
            zoom(by: 1 + event.magnification)
            return nil
        }
    }

    static let zoomRange: ClosedRange<CGFloat> = 0.1...3  // same floor as Fit

    /// Zooms keeping the graph point under the pointer (or the pane's center) in place.
    private func zoom(by factor: CGFloat) {
        let newScale = min(max(scale * factor, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        guard newScale != scale else { return }
        let anchor = pointer ?? CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)
        offset = clamped(Self.zoomedOffset(offset: offset, scale: scale, newScale: newScale, anchor: anchor), scale: newScale)
        scale = newScale
    }

    /// Screen point = offset + content point × scale; solve for the offset that keeps `anchor` fixed.
    static func zoomedOffset(offset: CGSize, scale: CGFloat, newScale: CGFloat, anchor: CGPoint) -> CGSize {
        let contentX = (anchor.x - offset.width) / scale
        let contentY = (anchor.y - offset.height) / scale
        return CGSize(width: anchor.x - contentX * newScale, height: anchor.y - contentY * newScale)
    }

    private func height(of node: JobGraph.Node) -> CGFloat {
        node.isGroup ? CGFloat(node.jobs.count) * groupRow + groupPadding * 2 : nodeSize.height
    }

    /// Boxes stacked per column; grouped boxes are taller.
    private var frames: [JobGraph.Node.ID: CGRect] {
        var frames: [JobGraph.Node.ID: CGRect] = [:]
        var nextY: [Int: CGFloat] = [:]
        for node in graph.nodes.sorted(by: { ($0.column, $0.row) < ($1.column, $1.row) }) {
            let y = nextY[node.column, default: 0]
            frames[node.id] = CGRect(x: CGFloat(node.column) * (nodeSize.width + columnGap), y: y,
                                     width: nodeSize.width, height: height(of: node))
            nextY[node.column] = y + height(of: node) + rowGap
        }
        return frames
    }

    private var canvasSize: CGSize {
        CGSize(width: CGFloat(graph.columns) * (nodeSize.width + columnGap) - columnGap,
               height: (frames.values.map(\.maxY).max() ?? 0) + rowGap)  // + a row gap for lanes under the last box
    }

    func frame(of id: JobGraph.Node.ID) -> CGRect? { frames[id] }

    /// Lines attach level with a box's first job, as on GitHub.
    func anchorY(of id: JobGraph.Node.ID) -> CGFloat? {
        guard let rect = frames[id], let node = graph.nodes.first(where: { $0.id == id }) else { return nil }
        return node.isGroup ? rect.minY + groupPadding + groupRow / 2 : rect.midY
    }

    private func endpoints(_ edge: JobGraph.Edge) -> ((rect: CGRect, y: CGFloat), (rect: CGRect, y: CGFloat))? {
        guard let from = frames[edge.from], let to = frames[edge.to],
              let fromY = anchorY(of: edge.from), let toY = anchorY(of: edge.to) else { return nil }
        return ((from, fromY), (to, toY))
    }

    /// Edges only run through the gaps between columns and rows, never across a node:
    /// adjacent columns get one elbow in the column gap; longer edges drop into a row gap,
    /// cross the skipped columns there, and come back up (or down) in the gap before the target.
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
                to.minY - rowGap / 2        // row gap just above the target
            } else if to.minY < from.minY {
                from.minY - rowGap / 2      // row gap just above the source
            } else {
                from.maxY + rowGap / 2      // same row: dip into the gap below it
            }
            points += [CGPoint(x: exitX, y: start.y), CGPoint(x: exitX, y: lane),
                       CGPoint(x: enterX, y: lane), CGPoint(x: enterX, y: end.y)]
        }
        points.append(end)
        return roundedPolyline(points)
    }

    /// A polyline whose corners are rounded, skipping zero-length segments.
    private func roundedPolyline(_ raw: [CGPoint]) -> Path {
        let points = raw.enumerated().filter { index, point in
            index == 0 || hypot(point.x - raw[index - 1].x, point.y - raw[index - 1].y) > 0.5
        }.map(\.element)
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for index in points.indices.dropFirst().dropLast() {
            let (previous, corner, next) = (points[index - 1], points[index], points[index + 1])
            let room = min(hypot(corner.x - previous.x, corner.y - previous.y),
                           hypot(next.x - corner.x, next.y - corner.y)) / 2
            path.addArc(tangent1End: corner, tangent2End: next, radius: min(10, room))
        }
        path.addLine(to: points.last!)
        return path
    }
}

private struct JobNode: View {
    @Environment(AppState.self) private var state
    @Environment(\.fontTheme) private var theme
    let job: WorkflowJob
    let isSelected: Bool
    let select: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: select) {
            HStack(spacing: 8 * theme.zoom) {
                Image(systemName: job.state.symbol)
                    .foregroundStyle(job.state.color)
                    .symbolEffect(.pulse, isActive: job.state.isActive && !reduceMotion)
                Text(job.name).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                if let duration = job.duration, job.state != .skipped {
                    Text(Duration.seconds(duration).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .themeFont(.callout)
            .padding(.horizontal, 12 * theme.zoom)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.primary.opacity(isHovered ? 0.09 : 0.05), in: .rect(cornerRadius: 8 * theme.zoom))
            .background(Color(nsColor: .windowBackgroundColor), in: .rect(cornerRadius: 8 * theme.zoom))  // opaque: hides lines behind
            .overlay {
                RoundedRectangle(cornerRadius: 8 * theme.zoom)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.15),
                                  lineWidth: (isSelected ? 2 : 1) * max(1, theme.zoom))
            }
            .contentShape(.rect(cornerRadius: 8 * theme.zoom))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu {
            if let url = job.htmlUrl {
                LinkActions(urls: [url])
            }
        }
        .help("\(job.name) — \(job.state.label)")
        .accessibilityLabel("\(job.name), \(job.state.label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Parallel jobs sharing the same neighbours, in one box with a selectable row per job.
private struct JobGroupNode: View {
    @Environment(\.fontTheme) private var theme
    let jobs: [WorkflowJob]
    let rowHeight: CGFloat
    let padding: CGFloat
    @Binding var selection: WorkflowJob.ID?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(jobs) { job in
                JobGroupRow(job: job, isSelected: selection == job.id) { selection = job.id }
                    .frame(height: rowHeight)
            }
        }
        .padding(.vertical, padding)
        .padding(.horizontal, 4 * theme.zoom)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 8 * theme.zoom))
        .background(Color(nsColor: .windowBackgroundColor), in: .rect(cornerRadius: 8 * theme.zoom))  // opaque: hides lines behind
        .overlay {
            RoundedRectangle(cornerRadius: 8 * theme.zoom).strokeBorder(Color.primary.opacity(0.15), lineWidth: max(1, theme.zoom))
        }
    }
}

private struct JobGroupRow: View {
    @Environment(\.fontTheme) private var theme
    let job: WorkflowJob
    let isSelected: Bool
    let select: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: select) {
            HStack(spacing: 8 * theme.zoom) {
                Image(systemName: job.state.symbol)
                    .foregroundStyle(job.state.color)
                    .symbolEffect(.pulse, isActive: job.state.isActive && !reduceMotion)
                Text(job.name).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                if let duration = job.duration, job.state != .skipped {
                    Text(Duration.seconds(duration).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .themeFont(.callout)
            .padding(.horizontal, 8 * theme.zoom)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isSelected ? Color.accentColor.opacity(0.25) : Color.primary.opacity(isHovered ? 0.06 : 0),
                        in: .rect(cornerRadius: 6 * theme.zoom))
            .contentShape(.rect(cornerRadius: 6 * theme.zoom))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu {
            if let url = job.htmlUrl { LinkActions(urls: [url]) }
        }
        .help("\(job.name) — \(job.state.label)")
        .accessibilityLabel("\(job.name), \(job.state.label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

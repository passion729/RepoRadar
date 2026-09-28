import SwiftUI

// Shared workspace chrome: filter tabs, search row, table/detail split, status bar, chips.
// The layout follows the Rockxy workbench model (tabs → search → table/detail → status bar).

enum DetailLayout: String {
    case bottom, right, hidden
}

enum SearchScope: String, CaseIterable, Identifiable {
    case all, title, repository, person

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All Fields"
        case .title: "Title"
        case .repository: "Repository"
        case .person: "Author"
        }
    }
}

/// Which workspace control keyboard focus is on; driven by the Find commands.
enum FocusTarget: Hashable {
    case search, sidebarFilter
}

// MARK: - Chips

extension View {
    /// Compact capsule chip: tinted when active, a faint neutral fill otherwise.
    func chipStyle(tint: Color = .accentColor, isActive: Bool = false, isHovered: Bool = false) -> some View {
        modifier(ChipModifier(tint: tint, isActive: isActive, isHovered: isHovered))
    }
}

private struct ChipModifier: ViewModifier {
    let tint: Color
    let isActive: Bool
    let isHovered: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .foregroundStyle(isActive ? tint : .primary)
            .background(fill, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(stroke, lineWidth: contrast == .increased ? 1 : 0.75)
            }
            .contentShape(Capsule(style: .continuous))
    }

    private var fill: Color {
        isActive ? tint.opacity(isHovered ? 0.24 : 0.16) : Color.primary.opacity(isHovered ? 0.08 : 0.0)
    }

    private var stroke: Color {
        isActive ? tint.opacity(0.35) : Color.primary.opacity(isHovered ? 0.12 : 0.0)
    }
}

/// A text tab in a strip, bold when selected.
struct TabChip: View {
    let title: String
    var count: Int?
    let isActive: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).fontWeight(isActive ? .semibold : .regular)
                if let count {
                    Text("\(count)").monospacedDigit().foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
            }
            .themeFont(.callout)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .frame(minHeight: 20)
            .chipStyle(isActive: isActive, isHovered: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

/// Small colored status pill, e.g. a red "Failed".
struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .themeFont(.caption, weight: .semibold)
            .lineLimit(1)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(color.opacity(0.16), in: Capsule(style: .continuous))
    }
}

/// Leading row marker in every table, like a traffic light for the row's state.
struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle().fill(color).frame(width: 7, height: 7)
    }
}

// MARK: - Bars

/// The row of filter tabs under the toolbar.
struct FilterTabBar<Option: Hashable & Identifiable>: View {
    @Binding var selection: Option
    let options: [Option]
    let title: (Option) -> String
    let count: (Option) -> Int?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                TabChip(title: title(option), count: count(option), isActive: selection == option) {
                    selection = option
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
    }
}

/// Field picker plus search field, placed in the content like a workbench filter row.
struct SearchRow: View {
    @Binding var text: String
    @Binding var scope: SearchScope
    var focus: FocusState<FocusTarget?>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Picker("Search in", selection: $scope) {
                ForEach(SearchScope.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search…", text: $text)
                    .textFieldStyle(.plain)
                    .focused(focus, equals: .search)
                    .onExitCommand { text = "" }
                if !text.isEmpty {
                    Button("Clear Search", systemImage: "xmark.circle.fill") { text = "" }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .themeFont(.callout)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }
}

/// Floating Liquid Glass status bar at the bottom of a workspace: actions · selection · stats.
struct StatusBar<Actions: View, Stats: View>: View {
    let selected: Int
    let visible: Int
    @ViewBuilder let actions: Actions
    @ViewBuilder let stats: Stats

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) { actions }
                .buttonStyle(.bordered)
                .controlSize(.small)
            Spacer(minLength: 12)
            Text("\(selected)/\(visible) rows selected")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer(minLength: 12)
            HStack(spacing: 12) { stats }
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .themeFont(.callout)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(height: 32)
        .glassEffect(.regular, in: .rect(cornerRadius: 10))
        .padding(6)
    }
}

// MARK: - Workspace

/// Tabs, search, a resizable table/detail split and a status bar, in Rockxy's workbench order.
struct Workspace<Tabs: View, Table: View, Detail: View, Status: View>: View {
    @AppStorage("detailLayout") private var layout: DetailLayout = .bottom
    @AppStorage("detailHeight") private var detailHeight = 340.0
    @AppStorage("detailWidth") private var detailWidth = 440.0
    @Binding var search: String
    @Binding var scope: SearchScope
    var focus: FocusState<FocusTarget?>.Binding
    @ViewBuilder let tabs: Tabs
    @ViewBuilder let table: Table
    @ViewBuilder let detail: Detail
    @ViewBuilder let status: Status

    var body: some View {
        VStack(spacing: 0) {
            tabs
            SearchRow(text: $search, scope: $scope, focus: focus)
            Divider()
            switch layout {
            case .bottom:
                PaneSplit(axis: .vertical, size: $detailHeight, minPrimary: 160, minDetail: 200) { table } detail: { detail }
            case .right:
                PaneSplit(axis: .horizontal, size: $detailWidth, minPrimary: 360, minDetail: 320) { table } detail: { detail }
            case .hidden:
                table.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // A plain stack item below the split, so it never overlaps the panes.
            status
        }
    }
}

// MARK: - Detail pieces

/// One-line summary above the detail panes, like a request line.
struct DetailHeader<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 8) { content }
            .themeFont(.callout)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A titled detail pane with its own tab strip.
struct DetailPane<Tab: Hashable & Identifiable, Content: View>: View {
    let title: String
    let tabs: [Tab]
    @Binding var selection: Tab
    let tabTitle: (Tab) -> String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).themeFont(.headline).padding(.horizontal, 12).padding(.top, 8)
            HStack(spacing: 2) {
                ForEach(tabs) { tab in
                    TabChip(title: tabTitle(tab), isActive: selection == tab) { selection = tab }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// Two detail panes side by side when the detail sits below the table, stacked when it sits to the right.
struct PanePair<Leading: View, Trailing: View>: View {
    @AppStorage("detailLayout") private var layout: DetailLayout = .bottom
    @AppStorage("detailSecondaryWidth") private var secondaryWidth = 520.0
    @AppStorage("detailSecondaryHeight") private var secondaryHeight = 220.0
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        if layout == .right {
            PaneSplit(axis: .vertical, size: $secondaryHeight, minPrimary: 140, minDetail: 120) {
                pane(leading)
            } detail: {
                pane(trailing)
            }
        } else {
            PaneSplit(axis: .horizontal, size: $secondaryWidth, minPrimary: 260, minDetail: 260) {
                pane(leading)
            } detail: {
                pane(trailing)
            }
        }
    }

    /// Panes clip at their top-left instead of letting oversized content (a wide graph) recenter them.
    private func pane(_ content: some View) -> some View {
        content
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
    }
}

/// Key / value rows in the style of a header table. Keys must be unique; they identify the rows.
struct KeyValue: Identifiable {
    let key: String
    let value: String
    var id: String { key }

    init(_ key: String, _ value: String) {
        self.key = key
        self.value = value
    }
}

struct KeyValueTable: View {
    let rows: [KeyValue]

    var body: some View {
        ScrollView {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 6) {
                ForEach(rows) { row in
                    GridRow {
                        Text(row.key).foregroundStyle(.secondary)
                        Text(row.value).textSelection(.enabled)
                    }
                }
            }
            .themeFont(.callout, mono: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct DetailPlaceholder: View {
    var body: some View {
        ContentUnavailableView("No Selection", systemImage: "rectangle.bottomhalf.inset.filled",
                               description: Text("Select a single row to see its details."))
            .frame(maxWidth: .infinity, maxHeight: .infinity)  // fill the pane so it centers
    }
}

extension SearchScope {
    func matches(_ query: String, title: String, repository: String, person: String, other: [String] = []) -> Bool {
        guard !query.isEmpty else { return true }
        let fields: [String] = switch self {
        case .all: [title, repository, person] + other
        case .title: [title]
        case .repository: [repository]
        case .person: [person]
        }
        return fields.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

/// Remaining GitHub API quota, shown at the end of every status bar.
struct QuotaLabel: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if let limit = state.rateLimit {
            Label("\(limit.remaining.formatted())/\(limit.limit.formatted())", systemImage: "gauge.with.dots.needle.33percent")
                .foregroundStyle(Double(limit.remaining) / Double(max(limit.limit, 1)) < 0.1 ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .help("GitHub API requests left this hour")
        }
    }
}

/// Table + detail split whose detail size is stored and changes only when the divider is dragged.
/// (VSplitView/HSplitView re-measure on every content change, so the pane jumped when switching rows.)
struct PaneSplit<Primary: View, Detail: View>: View {
    let axis: Axis
    @Binding var size: Double
    let minPrimary: CGFloat
    let minDetail: CGFloat
    @ViewBuilder let primary: Primary
    @ViewBuilder let detail: Detail
    @State private var dragStart: Double?

    var body: some View {
        GeometryReader { proxy in
            let total = axis == .vertical ? proxy.size.height : proxy.size.width
            let detailSize = clamp(size, total: total)
            let layout = axis == .vertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
            layout {
                primary
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
                handle(total: total)
                detail
                    .frame(width: axis == .horizontal ? detailSize : nil, height: axis == .vertical ? detailSize : nil)
                    .frame(maxWidth: axis == .vertical ? .infinity : nil, maxHeight: axis == .horizontal ? .infinity : nil,
                           alignment: .topLeading)
                    .clipped()
            }
        }
    }

    private func clamp(_ value: Double, total: CGFloat) -> CGFloat {
        min(max(CGFloat(value), minDetail), max(minDetail, total - minPrimary))
    }

    private func handle(total: CGFloat) -> some View {
        Divider()
            .overlay {
                // A wider invisible strip makes the 1 pt divider easy to grab.
                Color.clear
                    .frame(width: axis == .horizontal ? 8 : nil, height: axis == .vertical ? 8 : nil)
                    .contentShape(.rect)
                    .pointerStyle(axis == .vertical ? .rowResize : .columnResize)
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { drag in
                            let start = dragStart ?? Double(clamp(size, total: total))
                            dragStart = start
                            let delta = axis == .vertical ? drag.translation.height : drag.translation.width
                            size = Double(clamp(start - delta, total: total))
                        }
                        .onEnded { _ in dragStart = nil })
            }
            .zIndex(1)
    }
}

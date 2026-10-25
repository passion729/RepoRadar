import SwiftUI

// Shared pieces of the older detail views (pills, detail headers and panes, key/value tables, table focus).
// Pages move to the redesign's components phase by phase; what's left here goes with them.

/// Search shared by every page's list: each word must appear in one of the fields (case-insensitive).
func matchesSearch(_ query: String, _ fields: [String]) -> Bool {
    query.split(separator: " ").allSatisfy { word in fields.contains { $0.localizedCaseInsensitiveContains(word) } }
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
            Segmented(selection: $selection, segments: tabs.map { Segment(value: $0, title: tabTitle($0)) })
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            Rectangle().fill(Theme.separator).frame(height: 1)
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// Two detail panes stacked; the lower one keeps a height the user can drag.
struct PanePair<Leading: View, Trailing: View>: View {
    @AppStorage("detailSecondaryHeight") private var secondaryHeight = 260.0
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        SplitPane(axis: .vertical, sized: .second, size: $secondaryHeight, range: 120...800, minFlexible: 140) {
            leading
        } second: {
            trailing
        }
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

// MARK: - Table focus

extension View {
    /// Moves keyboard focus to the main table when its selection changes. After picking a sidebar item,
    /// the sidebar kept focus even though a row was clicked, so the new selection drew in inactive gray.
    func focusesTable<Value: Equatable>(onChangeOf selection: Value) -> some View {
        onChange(of: selection) {
            DispatchQueue.main.async {
                // The main window, even when it isn't key yet (keyWindow is nil while the app activates).
                for window in NSApp.windows where window.isVisible {
                    guard let table = mainTable(in: window.contentView) else { continue }
                    if window.firstResponder !== table { window.makeFirstResponder(table) }
                    return
                }
            }
        }
    }
}

extension View {
    /// Runs `action` once the selection has stayed put for the "autoReadSeconds" setting.
    /// Changing the selection cancels the timer.
    func autoRead<ID: Equatable>(_ selection: ID, when pending: Bool, _ action: @escaping () -> Void) -> some View {
        modifier(AutoRead(selection: selection, pending: pending, action: action))
    }
}

private struct AutoRead<ID: Equatable>: ViewModifier {
    @AppStorage("autoReadSeconds") private var seconds = 3
    let selection: ID
    let pending: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        content.task(id: selection) {
            guard seconds > 0, pending else { return }
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            action()
        }
    }
}

/// The multi-column table in the window; the sidebar and detail lists have a single column.
@MainActor private func mainTable(in view: NSView?) -> NSTableView? {
    guard let view else { return nil }
    // SwiftUI builds both on NSOutlineView; only the main table has several columns.
    if let table = view as? NSTableView, table.tableColumns.count > 3, !table.isHiddenOrHasHiddenAncestor {
        return table
    }
    for subview in view.subviews {
        if let table = mainTable(in: subview) { return table }
    }
    return nil
}

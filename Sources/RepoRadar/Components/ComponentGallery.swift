#if DEBUG
import SwiftUI

/// Debug window (Debug ▸ Component Gallery): every token and component, light and dark side by side.
struct ComponentGallery: View {
    @State private var toasts = ToastCenter()

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 0) {
                GalleryColumn(toasts: toasts).environment(\.colorScheme, .light)
                GalleryColumn(toasts: toasts).environment(\.colorScheme, .dark)
            }
        }
        .toasts(toasts)
        .frame(minWidth: 1100, minHeight: 600)
    }
}

private struct GalleryColumn: View {
    let toasts: ToastCenter
    @Environment(\.colorScheme) private var colorScheme
    @State private var queueFilter = "all"
    @State private var runFilter = "all"
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.section) {
            Text(colorScheme == .dark ? "Dark" : "Light").textStyle(.detailTitle)
            section("Colors") { colors }
            section("Type") { type }
            section("Buttons") { buttons }
            section("Icon buttons · search") { iconButtons }
            section("Segmented") {
                Segmented(selection: $queueFilter, segments: [
                    Segment(value: "all", title: "All", count: 6),
                    Segment(value: "reviews", title: "Reviews", count: 3),
                    Segment(value: "ci", title: "CI", count: 2),
                    Segment(value: "mentions", title: "Mentions", count: 0),
                ])
                Segmented(selection: $runFilter, segments: [
                    Segment(value: "all", title: "All", count: 26),
                    Segment(value: "failing", title: "Failing", count: 2, status: .failure),
                    Segment(value: "running", title: "Running", count: 2, status: .running),
                ])
            }
            section("Badges · Kbd") {
                HStack(spacing: 10) {
                    Badge(count: 12)
                    Badge(count: 6, tone: .blue)
                    Badge(count: 2, tone: .red)
                    Badge(count: 140, tone: .blue)
                    Divider().frame(height: 18)
                    ForEach(["E", "⌘K", "⇧⌘R", "⌘↵"], id: \.self) { Kbd($0) }
                }
            }
            section("Chips") {
                HStack(spacing: 6) {
                    Chip("Review requested", tone: .blue)
                    Chip("Your push failed", tone: .red)
                    Chip("Ready to merge", tone: .green)
                }
                HStack(spacing: 6) {
                    Chip("Approval needed", tone: .amber)
                    Chip("Mention", tone: .purple)
                    Chip("Author")
                }
                Chip("Compact", tone: .blue, systemImage: "eye", compact: true)
            }
            section("Status icons") {
                ForEach([14, 12, 10] as [CGFloat], id: \.self) { size in
                    HStack(spacing: 14) {
                        ForEach(StatusKind.allCases, id: \.self) { kind in
                            HStack(spacing: 4) {
                                StatusIcon(kind, size: size)
                                Text(kind.label).textStyle(.meta).foregroundStyle(Theme.Ink.secondary)
                            }
                        }
                    }
                }
            }
            section("Toast") {
                HStack {
                    Button("Show confirmation") {
                        toasts.show("Approved api-gateway #214") { toasts.show("Undone") }
                    }
                    Button("Show error") {
                        toasts.showError("GitHub HTTP 422: Pull request is not mergeable") {}
                    }
                }
                .buttonStyle(.secondary)
            }
        }
        .padding(Theme.Space.pane)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Theme.Ink.primary)
        .background(Theme.Surface.window)
        .background(colorScheme == .dark ? Color(hex: 0x1E1E22) : Color(hex: 0xF3F4F7))
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).textStyle(.label).foregroundStyle(Theme.Ink.tertiary)
            content()
        }
    }

    private var colors: some View {
        let tokens: [(String, Color)] = [
            ("surface.window", Theme.Surface.window), ("surface.sidebar", Theme.Surface.sidebar),
            ("surface.toolbar", Theme.Surface.toolbar), ("surface.pane", Theme.Surface.pane),
            ("surface.raised", Theme.Surface.raised), ("surface.log", Theme.Surface.log),
            ("text.primary", Theme.Ink.primary), ("text.body", Theme.Ink.body),
            ("text.secondary", Theme.Ink.secondary), ("text.tertiary", Theme.Ink.tertiary),
            ("text.link", Theme.Ink.link), ("separator", Theme.separator),
            ("fill.subtle", Theme.Fill.subtle), ("fill.hover", Theme.Fill.hover),
            ("selection.nav", Theme.Selection.nav), ("selection.row", Theme.Selection.row),
            ("accent", Theme.accent),
        ]
        return VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(tokens, id: \.0) { name, color in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 4).fill(color).frame(width: 28, height: 16)
                            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.separator) }
                        Text(name).textStyle(.meta).foregroundStyle(Theme.Ink.secondary)
                    }
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                ForEach(Tone.allCases, id: \.self) { tone in
                    GridRow {
                        Text(verbatim: "\(tone)").textStyle(.meta).foregroundStyle(Theme.Ink.secondary)
                        RoundedRectangle(cornerRadius: 4).fill(tone.solid).frame(width: 28, height: 16)
                        RoundedRectangle(cornerRadius: 4).fill(tone.tint).frame(width: 28, height: 16)
                        Text("Status text").textStyle(.rowTitle).foregroundStyle(tone.text)
                    }
                }
            }
        }
    }

    private var type: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(TextStyle.allCases, id: \.self) { style in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(verbatim: "\(style)").textStyle(.meta).foregroundStyle(Theme.Ink.tertiary).frame(width: 90, alignment: .leading)
                    Text(style == .bigNumber ? "12" : style == .log ? "1704 ✕ testNestedListIndent" : "RepoRadar 1234567890")
                        .textStyle(style)
                }
            }
        }
    }

    private var buttons: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                Text("Primary").textStyle(.meta).foregroundStyle(Theme.Ink.secondary)
                Button {} label: { HStack(spacing: 6) { Text("Approve"); Kbd("A") } }.buttonStyle(.primary)
                Button("Approve", systemImage: "checkmark") {}.buttonStyle(.primary)
                Button("Disabled") {}.buttonStyle(.primary).disabled(true)
            }
            GridRow {
                Text("Secondary").textStyle(.meta).foregroundStyle(Theme.Ink.secondary)
                Button("Request changes") {}.buttonStyle(.secondary)
                Button("Re-run failed", systemImage: "arrow.clockwise") {}.buttonStyle(.secondary)
                Button("Disabled") {}.buttonStyle(.secondary).disabled(true)
            }
            GridRow {
                Text("Ghost").textStyle(.meta).foregroundStyle(Theme.Ink.secondary)
                Button {} label: { HStack(spacing: 6) { Text("Done"); Kbd("E") } }.buttonStyle(.ghost)
                Button("Snooze", systemImage: "clock") {}.buttonStyle(.ghost)
                Button("Disabled") {}.buttonStyle(.ghost).disabled(true)
            }
            GridRow {
                Text("Merge").textStyle(.meta).foregroundStyle(Theme.Ink.secondary)
                Button("Squash and merge") {}.buttonStyle(.merge)
                Button("Compact") {}.buttonStyle(.merge).controlSize(.small)
                Button("Disabled") {}.buttonStyle(.merge).disabled(true)
            }
        }
    }

    private var iconButtons: some View {
        HStack(spacing: 12) {
            Button("Refresh", systemImage: "arrow.clockwise") {}.buttonStyle(.icon).help("Refresh")
            IconButtonGroup {
                Button("Refresh", systemImage: "arrow.clockwise") {}
                Button("Filter", systemImage: "line.3.horizontal.decrease") {}
                Button("Notifications", systemImage: "bell") {}
            }
            SearchField(prompt: "Search or jump to…", text: $search).frame(width: 260)
        }
    }
}
#endif

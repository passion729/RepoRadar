import SwiftUI

/// Menu bar icon: the radar mark, a warning triangle while workflows fail, and a count of what needs attention.
struct MenuBarLabel: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let attention = state.failingCount + state.reviewRequestCount + state.unreadCount
        HStack(spacing: 3) {
            Image(systemName: state.failingCount > 0 ? "exclamationmark.triangle.fill" : "dot.radiowaves.left.and.right")
            if attention > 0 {
                Text("\(attention)").monospacedDigit()
            }
        }
        .accessibilityLabel(attention > 0 ? "RepoRadar, \(attention) items need attention" : "RepoRadar")
    }
}

struct MenuBarContent: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    private let limit = 5

    var body: some View {
        let failing = state.latestRuns.filter { $0.state == .failure }.sorted { $0.createdAt > $1.createdAt }
        let running = state.latestRuns.filter(\.state.isActive).sorted { $0.createdAt > $1.createdAt }
        let reviews = state.pulls.filter { $0.roles.contains(.reviewRequested) }.sorted { $0.updatedAt > $1.updatedAt }
        let unread = state.notifications.filter(\.unread)

        header

        if state.hasToken, failing.isEmpty, running.isEmpty, reviews.isEmpty, unread.isEmpty {
            Divider()
            item("All clear", symbol: "checkmark.circle.fill", color: .systemGreen) {}
        }

        section("Failing", count: failing.count, show: .actions) {
            ForEach(failing.prefix(limit)) { run in
                item("\(run.workflowName) · \(repoName(run.repo))", symbol: RunState.failure.symbol, color: .systemRed) {
                    state.open([run.htmlUrl])
                }
            }
        }
        section("Running", count: running.count, show: .actions) {
            ForEach(running.prefix(limit)) { run in
                item("\(run.workflowName) · \(repoName(run.repo))", symbol: RunState.running.symbol, color: .systemOrange) {
                    state.open([run.htmlUrl])
                }
            }
        }
        section("Review Requests", count: reviews.count, show: .pulls) {
            ForEach(reviews.prefix(limit)) { item in
                self.item("#\(item.pr.number) \(item.title)", symbol: "arrow.triangle.pull", color: .systemPurple) {
                    state.open([item.pr.htmlUrl])
                }
            }
        }
        section("Unread", count: unread.count, show: .inbox) {
            ForEach(unread.prefix(limit)) { item in
                self.item(item.title, symbol: item.symbol, color: item.subject.type == "CheckSuite" ? .systemRed : .systemBlue) {
                    state.open([item.webURL])
                }
            }
            self.item("Mark All as Read", symbol: "envelope.open", color: .secondaryLabelColor) { state.markRead(unread) }
        }

        Divider()
        Button("Open RepoRadar") { show(nil) }
            .keyboardShortcut("o")
        Button("Refresh Now") { Task { await state.refresh() } }
            .keyboardShortcut("r")
            .disabled(state.isRefreshing || !state.hasToken)
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Divider()
        Button("Quit RepoRadar") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    @ViewBuilder private var header: some View {
        if !state.hasToken {
            Text("Not signed in to GitHub")
            SettingsLink { Text("Sign In…") }
        } else {
            Text(state.login.map { "RepoRadar · @\($0)" } ?? "RepoRadar")
            if let error = state.error {
                Text("⚠︎ \(error)").lineLimit(2)
            } else if state.isRefreshing {
                Text("Updating…")
            } else if let date = state.lastUpdated {
                Text("Updated \(date.formatted(date: .omitted, time: .shortened))")
            }
        }
    }

    /// A titled group with at most `limit` items and a jump into the matching section of the main window.
    @ViewBuilder private func section(_ title: String, count: Int, show item: SidebarItem,
                                      @ViewBuilder content: () -> some View) -> some View {
        if count > 0 {
            Section("\(title) (\(count))") {
                content()
                if count > limit {
                    Button("Show All \(count) in RepoRadar…") { show(item) }
                }
            }
        }
    }

    /// A menu item with a colored SF Symbol. Menus render SwiftUI symbols as monochrome templates,
    /// so the icon is pre-colored as a non-template NSImage.
    private func item(_ title: String, symbol: String, color: NSColor, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                if let image = Self.colored(symbol, color) { Image(nsImage: image) }
            }
        }
    }

    static func colored(_ symbol: String, _ color: NSColor) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        image?.isTemplate = false
        return image
    }

    private func show(_ item: SidebarItem?) {
        if let item { state.requestedSection = item }
        openWindow(id: "main")
        NSApp.activate()
    }

    private func repoName(_ repo: String) -> String {
        repo.split(separator: "/").last.map(String.init) ?? repo
    }
}

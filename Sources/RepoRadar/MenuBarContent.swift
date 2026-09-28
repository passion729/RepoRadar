import AppKit
import SwiftUI

/// The menu bar item: an icon with an attention count that opens a SwiftUI panel in a popover.
/// (NSMenu, from SwiftUI or AppKit, doesn't show item icons here, so a panel carries the colors.)
@MainActor
final class MenuBarController: NSObject {
    static var shared: MenuBarController?

    private let state: AppState
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    /// Set by the main window, which is the only place SwiftUI's `openWindow` is available.
    var openMainWindow: (() -> Void)?

    init(state: AppState) {
        self.state = state
        super.init()
        popover.behavior = .transient  // closes on outside click and Esc
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: MenuBarPanel(controller: self)
            .environment(state)
            .appliesFontTheme())
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)
        updateButton()
    }

    @objc private func toggle() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func close() { popover.performClose(nil) }

    /// Radar mark, or a warning triangle while workflows fail, plus a count of what needs attention.
    private func updateButton() {
        withObservationTracking {
            let attention = state.failingCount + state.reviewRequestCount + state.unreadCount
            let symbol = state.failingCount > 0 ? "exclamationmark.triangle.fill" : "dot.radiowaves.left.and.right"
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "RepoRadar")
            image?.isTemplate = true
            statusItem.button?.image = image
            statusItem.button?.imagePosition = .imageLeading
            statusItem.button?.title = attention > 0 ? " \(attention)" : ""
            statusItem.button?.setAccessibilityLabel(attention > 0 ? "RepoRadar, \(attention) items need attention" : "RepoRadar")
        } onChange: { [weak self] in
            Task { @MainActor in self?.updateButton() }
        }
    }

    func show(_ section: SidebarItem?) {
        close()
        if let section { state.requestedSection = section }
        openMainWindow?()
        NSApp.activate()
    }

    func openSettings() {
        close()
        NSApp.activate()
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

/// Hands SwiftUI's `openWindow` (only available inside a scene) to the menu bar item.
struct MenuBarWindowOpener: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear.onAppear {
            MenuBarController.shared?.openMainWindow = { openWindow(id: "main") }
        }
    }
}

// MARK: - Panel

private enum PanelTab: CaseIterable, Identifiable {
    case failing, reviews, unread, running

    var id: Self { self }

    var title: String {
        switch self {
        case .failing: "Failing"
        case .reviews: "Reviews"
        case .unread: "Unread"
        case .running: "Running"
        }
    }

    var symbol: String {
        switch self {
        case .failing: RunState.failure.symbol
        case .reviews: "arrow.triangle.pull"
        case .unread: "tray.full.fill"
        case .running: RunState.running.symbol
        }
    }

    var color: Color {
        switch self {
        case .failing: .red
        case .reviews: .purple
        case .unread: .blue
        case .running: .orange
        }
    }

    var section: SidebarItem {
        switch self {
        case .failing, .running: .actions
        case .reviews: .pulls
        case .unread: .inbox
        }
    }
}

/// One row in the panel: something to open, with a colored icon.
private struct PanelRow: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
    let date: Date
    let url: URL
    var notification: GitHubNotification?
}

struct MenuBarPanel: View {
    @Environment(AppState.self) private var state
    let controller: MenuBarController
    @State private var tab: PanelTab?

    var body: some View {
        VStack(spacing: 0) {
            header
            if state.hasToken {
                tiles.padding(.horizontal, 12).padding(.bottom, 10)
                Divider()
                list
            } else {
                signedOut
            }
            Divider()
            footer
        }
        .frame(width: 380)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .themeFont(.title3, weight: .semibold)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("RepoRadar").themeFont(.headline)
                Text(status).themeFont(.caption).foregroundStyle(state.error == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                    .lineLimit(1)
            }
            Spacer()
            RefreshButton()
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
        }
        .padding(12)
    }

    private var status: String {
        if let error = state.error { return error }
        let who = state.login.map { "@\($0)" } ?? ""
        if state.isRefreshing { return "\(who) · Updating…" }
        guard let date = state.lastUpdated else { return who }
        return "\(who) · Updated \(date.formatted(date: .omitted, time: .shortened))"
    }

    // MARK: Tiles

    private var tiles: some View {
        HStack(spacing: 8) {
            ForEach(PanelTab.allCases) { option in
                let count = rows(for: option).count
                Button { tab = option } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Image(systemName: option.symbol)
                            .foregroundStyle(count > 0 ? option.color : .secondary)
                        Text("\(count)").themeFont(.title2, weight: .semibold).monospacedDigit()
                            .foregroundStyle(count > 0 ? .primary : .secondary)
                        Text(option.title).themeFont(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(option.color.opacity(selectedTab == option ? 0.22 : count > 0 ? 0.1 : 0.04),
                                in: .rect(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(selectedTab == option ? option.color.opacity(0.6) : .clear, lineWidth: 1.5)
                    }
                    .contentShape(.rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(count) \(option.title)")
                .accessibilityAddTraits(selectedTab == option ? .isSelected : [])
            }
        }
    }

    /// The chosen tab, or the most urgent one with items.
    private var selectedTab: PanelTab {
        tab ?? PanelTab.allCases.first { !rows(for: $0).isEmpty } ?? .failing
    }

    // MARK: List

    @ViewBuilder private var list: some View {
        let rows = rows(for: selectedTab)
        if rows.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
                Text(allClear ? "All clear" : "Nothing \(selectedTab.title.lowercased())").themeFont(.headline)
                Text(allClear ? "No failures, reviews or unread notifications." : "Pick another tile above.")
                    .themeFont(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(rows) { row in
                        PanelRowView(row: row, open: {
                            state.open([row.url])
                            controller.close()
                        }, markRead: row.notification.map { note in { state.markRead([note]) } })
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 360)
            .fixedSize(horizontal: false, vertical: rows.count <= 6)
        }
    }

    private var allClear: Bool { PanelTab.allCases.allSatisfy { rows(for: $0).isEmpty } }

    private func rows(for tab: PanelTab) -> [PanelRow] {
        switch tab {
        case .failing, .running:
            let runs = state.latestRuns
                .filter { tab == .failing ? $0.state == .failure : $0.state.isActive }
                .sorted { $0.createdAt > $1.createdAt }
            return runs.map { run in
                PanelRow(id: "run-\(run.id)", title: run.workflowName, subtitle: "\(run.repo) · \(run.branchName)",
                         symbol: run.state.symbol, color: tab.color, date: run.createdAt, url: run.htmlUrl)
            }
        case .reviews:
            return state.pulls.filter { $0.roles.contains(.reviewRequested) }.sorted { $0.updatedAt > $1.updatedAt }.map { pull in
                PanelRow(id: "pr-\(pull.id)", title: pull.title, subtitle: "\(pull.repo) #\(pull.pr.number) · \(pull.author)",
                         symbol: "arrow.triangle.pull", color: .purple, date: pull.updatedAt, url: pull.pr.htmlUrl)
            }
        case .unread:
            return state.notifications.filter(\.unread).map { note in
                PanelRow(id: "n-\(note.id)", title: note.title, subtitle: "\(note.repo) · \(note.reasonLabel)",
                         symbol: note.symbol, color: note.subject.type == "CheckSuite" ? .red : .blue,
                         date: note.updatedAt, url: note.webURL, notification: note)
            }
        }
    }

    // MARK: Footer

    private var signedOut: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.questionmark").font(.largeTitle).foregroundStyle(.secondary)
            Text("Not signed in to GitHub").themeFont(.headline)
            Button("Sign In…") { controller.openSettings() }.buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Open RepoRadar") { controller.show(state.hasToken ? selectedTab.section : nil) }
                .buttonStyle(.glass)
            if selectedTab == .unread, state.unreadCount > 0 {
                Button("Mark All Read") { state.markRead(state.notifications.filter(\.unread)) }
                    .buttonStyle(.glass)
            }
            Spacer()
            Button("Settings", systemImage: "gearshape") { controller.openSettings() }
                .labelStyle(.iconOnly).buttonStyle(.borderless).help("Settings")
            Button("Quit RepoRadar", systemImage: "power") { NSApp.terminate(nil) }
                .labelStyle(.iconOnly).buttonStyle(.borderless).help("Quit RepoRadar")
        }
        .controlSize(.small)
        .padding(10)
    }
}

private struct PanelRowView: View {
    let row: PanelRow
    let open: () -> Void
    let markRead: (() -> Void)?
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: row.symbol)
                .foregroundStyle(row.color)
                .frame(width: 28, height: 28)
                .background(row.color.opacity(0.15), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).themeFont(.body, weight: .medium).lineLimit(1)
                Text(row.subtitle).themeFont(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if isHovered, let markRead {
                Button("Mark as Read", systemImage: "checkmark.circle", action: markRead)
                    .labelStyle(.iconOnly).buttonStyle(.borderless).help("Mark as Read")
            } else {
                Text(row.date, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                    .themeFont(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isHovered ? Color.primary.opacity(0.07) : .clear, in: .rect(cornerRadius: 8))
        .contentShape(.rect(cornerRadius: 8))
        .onTapGesture(perform: open)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Open", open)
    }
}

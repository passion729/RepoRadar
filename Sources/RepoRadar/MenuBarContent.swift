import AppKit
import SwiftUI

/// The menu bar item (M1–M5): an NSStatusItem with a colored dot, opening a SwiftUI panel in a popover.
/// (Not MenuBarExtra: its label is drawn as a template, which can't carry the red or blue dot.)
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
        updateVisibility()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updateVisibility() }
        }
    }

    @objc func toggle() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func close() { popover.performClose(nil) }

    /// Settings ▸ General ▸ Show RepoRadar in the menu bar.
    private func updateVisibility() {
        let visible = UserDefaults.standard.object(forKey: "showMenuBarIcon") as? Bool ?? true
        if statusItem.isVisible != visible { statusItem.isVisible = visible }
    }

    /// M1: the radar, tinted red with the count of unseen failing workflows, blue when only reviews
    /// wait, a pause mark while alerts are paused; dimmed when offline or signed out.
    private func updateButton() {
        withObservationTracking {
            guard let button = statusItem.button else { return }
            let failing = state.failingCount  // unseen only: a failure stops counting once you've viewed it
            let reviews = state.needsYou.count { $0.category == .review }
            var image = NSImage(systemSymbolName: "dot.radiowaves.left.and.right", accessibilityDescription: "RepoRadar")
            let tint = failing > 0 ? NSColor(Tone.red.solid) : reviews > 0 ? NSColor.systemBlue : nil  // brand blue is too dark as thin strokes on a dark menu bar
            if let tint { image = image?.withSymbolConfiguration(.init(paletteColors: [tint])) }
            image?.isTemplate = tint == nil
            button.image = image
            button.imagePosition = .imageLeading

            let title = NSMutableAttributedString()
            if failing > 0 {
                title.append(NSAttributedString(string: "\u{2009}\(failing)", attributes: [.font: NSFont.menuBarFont(ofSize: 0), .foregroundColor: NSColor.labelColor]))
            }
            if state.alertsPaused {
                let pause = NSTextAttachment()
                pause.image = NSImage(systemSymbolName: "bell.slash.fill", accessibilityDescription: "Alerts paused")
                title.append(NSAttributedString(string: "\u{2009}"))
                title.append(NSAttributedString(attachment: pause))
            }
            button.attributedTitle = title
            let status = state.syncStatus
            button.appearsDisabled = status == .offline || status == .signInAgain
            var label = "RepoRadar"
            if failing > 0 { label += ", \(failing) failing" } else if reviews > 0 { label += ", reviews waiting" }
            if state.alertsPaused { label += ", alerts paused" }
            button.setAccessibilityLabel(label)
            // The count changes the button's width; keep an open popover pointing at it.
            if popover.isShown {
                button.superview?.layoutSubtreeIfNeeded()
                popover.positioningRect = button.bounds
            }
        } onChange: { [weak self] in
            Task { @MainActor in self?.updateButton() }
        }
    }

    /// Closes the panel and brings the main window forward on a page (and a list, filter or item).
    func show(_ page: Page?, select request: SelectionRequest? = nil) {
        close()
        if let page { state.navigate(to: page, select: request) }
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

struct MenuBarPanel: View {
    @Environment(AppState.self) private var state
    let controller: MenuBarController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if state.hasToken {
                tiles
                queue
                running
            } else {
                signedOut
            }
            footer
        }
        .padding(16)
        .frame(width: 400)
        .toasts(state.toasts)
    }

    // MARK: Header and numbers (M2)

    private var header: some View {
        HStack(spacing: 8) {
            Text("RepoRadar").textStyle(.toolbarTitle).foregroundStyle(Theme.Ink.primary)
            Circle().fill(state.syncStatus.tone.solid).frame(width: 7, height: 7)
            TimelineView(.periodic(from: .now, by: 5)) { _ in
                Text(status).textStyle(.meta).foregroundStyle(Theme.Ink.secondary).lineLimit(1)
            }
            .help(state.rateLimit.map { "\($0.remaining.formatted()) API calls left this hour" } ?? "")
            Spacer()
            Button("Settings", systemImage: "gearshape") { controller.openSettings() }
                .buttonStyle(IconButtonStyle(diameter: 28))
                .help("Settings")
        }
    }

    /// Sync state only; the quota is in the tooltip and the main window's sidebar.
    private var status: String {
        guard case .live = state.syncStatus else { return state.syncStatus.title }
        guard let age = state.lastUpdated?.shortAge() else { return "Live" }
        return age == "now" ? "synced just now" : "synced \(age) ago"
    }

    private var tiles: some View {
        HStack(spacing: 8) {
            tile(state.needsYou.count { $0.category == .review }, "Reviews", Tone.blue.text) {
                controller.show(.now, select: .queueFilter(.reviews))
            }
            tile(state.scopedFailingCount, "Failing", Tone.red.text) { controller.show(.actions, select: .runFilter(.failing)) }
            tile(state.runningRuns.count, "Running", Tone.amber.text) { controller.show(.actions, select: .runFilter(.running)) }
            tile(state.scopedUnreadCount, "Unread", Theme.Ink.primary) { controller.show(.inbox, select: .inboxFilter(.unread)) }
        }
    }

    private func tile(_ count: Int, _ title: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count)").font(.system(size: 22, weight: .semibold).monospacedDigit())
                    .foregroundStyle(count == 0 ? Theme.Ink.tertiary : color)
                Text(title).textStyle(.meta).foregroundStyle(Theme.Ink.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Theme.Surface.raised.opacity(0.7), in: .rect(cornerRadius: 12))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(count) \(title)")
    }

    // MARK: Needs you, top 4 (M3)

    @ViewBuilder private var queue: some View {
        let items = state.needsYou
        VStack(alignment: .leading, spacing: 4) {
            Text("Needs you").textStyle(.label).foregroundStyle(Theme.Ink.secondary)
            if items.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Tone.green.solid)
                    Text("You're all caught up").textStyle(.meta).foregroundStyle(Theme.Ink.secondary)
                }
                .padding(.vertical, 6)
            }
            ForEach(Array(items.prefix(4).enumerated()), id: \.element.id) { index, item in
                PanelQueueRow(item: item, isFirst: index == 0, controller: controller)
            }
            if items.count > 4 {
                Button("+\(items.count - 4) more in RepoRadar") { controller.show(.now) }
                    .buttonStyle(.plain)
                    .textStyle(.meta)
                    .foregroundStyle(Theme.Ink.link)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: Running (M4)

    @ViewBuilder private var running: some View {
        let runs = state.runningRuns
        if !runs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Running · \(eta(runs))").textStyle(.label).foregroundStyle(Theme.Ink.secondary)
                ForEach(runs.prefix(3)) { run in
                    PanelRunRow(run: run) { controller.show(.actions, select: .run(run.id)) }
                }
                Toggle("Notify me when these finish", isOn: Binding(get: { !state.watchedRuns.isEmpty },
                                                                     set: { state.watchRunning($0) }))
                    .toggleStyle(.checkbox)
                    .textStyle(.meta)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Fill.subtle, in: .rect(cornerRadius: 14))
        }
    }

    private func eta(_ runs: [WorkflowRun]) -> String {
        let left = runs.compactMap { run in state.usualDuration(of: run).map { RunStats.remaining(elapsed: run.duration, usual: $0) } }
        guard let longest = left.max() else { return "\(runs.count) in progress" }
        return longest <= 60 ? "finishing now" : "all done in about \(Int((longest / 60).rounded())) min"
    }

    // MARK: Footer (M5)

    private var signedOut: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.questionmark").font(.largeTitle).foregroundStyle(Theme.Ink.tertiary)
            Text("Not signed in to GitHub").textStyle(.rowTitle)
            Button("Sign In…") { controller.openSettings() }.buttonStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button { controller.show(nil) } label: {
                HStack(spacing: 6) { Text("Open RepoRadar"); Kbd("⌘0") }.frame(maxWidth: .infinity)
            }
            .buttonStyle(.primary)
            .keyboardShortcut("0")
            if state.alertsPaused, let until = state.alertsPausedUntil {
                Button { state.resumeAlerts() } label: {
                    Text("Resume alerts").frame(maxWidth: .infinity)
                }
                .buttonStyle(.secondary)
                .help("Alerts are paused until \(until.formatted(date: .omitted, time: .shortened))")
            } else {
                Button { state.pauseAlerts(for: 3600) } label: { Text("Pause for 1 hour").frame(maxWidth: .infinity) }
                    .buttonStyle(.secondary)
                    .help("Pause alerts for 1 hour")
            }
        }
    }
}

/// One Needs-you item with its one action: Re-run and Approve happen here (undoable); Review, Reply and the
/// rest open the main window on it.
private struct PanelQueueRow: View {
    @Environment(AppState.self) private var state
    let item: NeedsYouItem
    let isFirst: Bool
    let controller: MenuBarController
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tone.text)
                .frame(width: 28, height: 28)
                .background(tone.tint, in: .rect(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).textStyle(.rowTitle).foregroundStyle(Theme.Ink.primary).lineLimit(1)
                Text(meta).textStyle(.meta).foregroundStyle(Theme.Ink.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            if isFirst {
                Button(action.title, action: perform).buttonStyle(.primary).controlSize(.small)
            } else {
                Button(action.title, action: perform).buttonStyle(.secondary).controlSize(.small)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(isHovered ? Theme.Fill.hover : .clear, in: .rect(cornerRadius: 10))
        .contentShape(.rect)
        .onTapGesture { controller.show(.now, select: .queueItem(item.id)) }
        .onHover { isHovered = $0 }
        .requiresPermission(action.inPanel ? state.writeBlockedReason : nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) { controller.show(.now, select: .queueItem(item.id)) }
        .accessibilityAction(named: action.title, perform)
    }

    private var action: (title: String, inPanel: Bool) {
        switch item.kind {
        case .pushFailed: ("Re-run", true)
        case .deployment: ("Approve", true)
        case .review: ("Review", false)
        case .mention: ("Reply", false)
        case .mergeable: ("Merge…", false)
        case .changesRequested: ("Open", false)
        }
    }

    private func perform() {
        switch item.kind {
        case .pushFailed(let run): state.rerunFailedJobs([run], item: item)
        case .deployment: state.reviewDeployment(item, approve: true)
        case .review(let pull, _, _): controller.show(.pulls, select: .pull(pull.id))
        case .mention, .mergeable, .changesRequested: controller.show(.now, select: .queueItem(item.id))
        }
    }

    private var symbol: String {
        switch item.kind {
        case .pushFailed: "xmark"
        case .deployment: "checkmark.shield"
        case .review: "arrow.triangle.pull"
        case .mention: "at"
        case .mergeable: "arrow.triangle.merge"
        case .changesRequested: "exclamationmark.bubble"
        }
    }

    private var tone: Tone {
        switch item.kind {
        case .pushFailed, .changesRequested: .red
        case .deployment: .amber
        case .review: .blue
        case .mention: .purple
        case .mergeable: .green
        }
    }

    private var meta: String {
        let repo = item.repo.split(separator: "/").last.map(String.init) ?? item.repo
        let what = switch item.kind {
        case .pushFailed(let run): "#\(run.runNumber) · \(run.branchName)"
        case .deployment(let run, _): "\(run.workflowName) #\(run.runNumber)"
        case .review(let pull, _, _): "#\(pull.number) · review"
        case .mention(let note): note.ref.map { "#\($0.number)" } ?? "mention"
        case .mergeable(let pull), .changesRequested(let pull): "#\(pull.number)"
        }
        return "\(repo) \(what) · \(item.since.shortAge())"
    }
}

/// A running run with one progress bar (5 pt) and the time left by its usual duration (M4).
private struct PanelRunRow: View {
    @Environment(AppState.self) private var state
    let run: WorkflowRun
    let open: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let usual = state.usualDuration(of: run)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    StatusIcon(.running, size: 12)
                    Text(run.repo.split(separator: "/").last.map(String.init) ?? run.repo)
                        .textStyle(.rowTitle).foregroundStyle(Theme.Ink.primary)
                    Text("\(run.workflowName) · \(run.branchName)").textStyle(.meta).foregroundStyle(Theme.Ink.secondary).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(usual.map { left($0) } ?? RunStats.clock(run.duration))
                        .textStyle(.meta).foregroundStyle(Theme.Ink.secondary)
                }
                GeometryReader { proxy in
                    let fraction = usual.map { min(0.97, run.duration / max($0, 1)) } ?? 0.5
                    Capsule().fill(Theme.Fill.subtle)
                        .overlay(alignment: .leading) {
                            Capsule().fill(Color(hex: 0xF0A020)).frame(width: proxy.size.width * fraction)
                        }
                }
                .frame(height: 5)
                .padding(.leading, 20)
            }
        }
        .contentShape(.rect)
        .onTapGesture(perform: open)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, open)
    }

    private func left(_ usual: TimeInterval) -> String {
        let remaining = RunStats.remaining(elapsed: run.duration, usual: usual)
        return remaining >= 0 ? "~\(RunStats.clock(remaining)) left" : RunStats.remainingText(elapsed: run.duration, usual: usual)
    }
}

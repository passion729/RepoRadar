import SwiftUI

/// Inbox (I1–I9): every GitHub notification on the left (430 pt), the conversation on the right.
struct InboxView: View {
    @Environment(AppState.self) private var state
    let search: String
    let toolbar: StandardToolbar
    @SceneStorage("inboxFilter") private var filter: InboxFilter = .unread
    @SceneStorage("inboxListWidth") private var listWidth = 430.0
    @AppStorage("inboxGrouping") private var grouping: InboxGrouping = .time
    @State private var selection: String?
    @State private var expandedBots: Set<String> = []
    @State private var snoozing: String?
    @FocusState private var isListFocused: Bool

    var body: some View {
        let visible = visibleThreads
        SplitPane(size: $listWidth, range: 340...560, minFlexible: 360) {
            VStack(spacing: 0) {
                ScrollView(.horizontal) {
                    Segmented(selection: $filter, segments: InboxFilter.allCases.map { option in
                        Segment(value: option, title: option.title, count: scopedThreads.count(where: option.matches))
                    })
                    .padding(12)
                }
                .scrollIndicators(.never)
                list(visible)
                Rectangle().fill(Theme.separator).frame(height: 1)
                footer
            }
        } second: {
            detail
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Mark All Read") { markAllRead(visible) }
                    .disabled(!visible.contains(where: \.unread))
                    .help("Mark everything in this list read")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu("Group", systemImage: "rectangle.grid.1x2") {
                    Picker("Group", selection: $grouping) {
                        ForEach(InboxGrouping.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                }
                .help("Group notifications")
            }
            toolbar
        }
        .focusedSceneValue(\.selectedNotifications, selectedThreads)
        .focusedSceneValue(\.selectedURLs, selectedThreads.map(\.webURL))
        .autoRead(selection, when: selectedThreads.count == 1 && selectedThreads[0].unread) { state.markRead(selectedThreads) }
        .onChange(of: visible.map(\.id)) { old, new in
            // A handled thread leaves the list: select the one that took its place.
            guard let selection, !new.contains(selection), let index = old.firstIndex(of: selection) else { return }
            self.selection = new.isEmpty ? nil : new[min(index, new.count - 1)]
        }
        .onChange(of: state.requestedSelection, initial: true) {
            if case .inboxFilter(let option)? = state.requestedSelection {
                filter = option
                state.requestedSelection = nil
                return
            }
            guard case .thread(let id)? = state.requestedSelection else { return }
            if !(state.notifications.first { $0.id == id }.map(filter.matches) ?? true) { filter = .all }
            selection = id
            state.requestedSelection = nil
        }
    }

    // MARK: List

    private func list(_ visible: [GitHubNotification]) -> some View {
        let sections = Inbox.sections(visible, grouping: grouping, authors: authors)
        return Group {
            if state.lastUpdated == nil && state.hasToken {
                SkeletonRows().padding(.horizontal, 8)
                Spacer()
            } else if visible.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2, pinnedViews: []) {
                            ForEach(sections) { section in
                                Text(section.title)
                                    .textStyle(.label)
                                    .foregroundStyle(Theme.Ink.tertiary)
                                    .padding(.horizontal, 12)
                                    .padding(.top, 10)
                                    .padding(.bottom, 4)
                                ForEach(section.entries) { entry in
                                    row(entry)
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                    }
                    .focusable()
                    .focused($isListFocused)
                    .focusEffectDisabled()
                    .onKeyPress(phases: .down) { handleKey($0, order: order(sections)) }
                    .focusedValue(\.listCommands, isListFocused ? commands(order(sections)) : nil)
                    .onChange(of: selection) { _, id in
                        guard let id else { return }
                        withAnimation(.snappy) { proxy.scrollTo(id) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func row(_ entry: InboxEntry) -> some View {
        switch entry {
        case .thread(let thread):
            NotificationRow(thread: thread, isSelected: selection == thread.id, authors: authors,
                            isSnoozing: snoozeBinding(thread.id)) { select(thread.id) }
                .id(thread.id)
        case .bots(let threads):
            BotBundleRow(threads: threads, isExpanded: expandedBots.contains(entry.id)) {
                if expandedBots.contains(entry.id) { expandedBots.remove(entry.id) } else { expandedBots.insert(entry.id) }
            }
            .id(entry.id)
            if expandedBots.contains(entry.id) {
                ForEach(threads) { thread in
                    NotificationRow(thread: thread, isSelected: selection == thread.id, authors: authors,
                                    isSnoozing: snoozeBinding(thread.id)) { select(thread.id) }
                        .padding(.leading, 20)
                        .id(thread.id)
                }
            }
        }
    }

    /// Rows in display order, for J/K (a collapsed bundle counts as its first thread).
    private func order(_ sections: [InboxSection]) -> [String] {
        sections.flatMap(\.entries).flatMap { entry -> [String] in
            switch entry {
            case .thread(let thread): [thread.id]
            case .bots(let threads): expandedBots.contains(entry.id) ? threads.map(\.id) : [threads[0].id]
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            hint("E", "done")
            hint("S", "snooze")
            hint("⇧⌘U", "read")
            hint("M", "mute thread")
            Spacer()
        }
        .textStyle(.meta)
        .foregroundStyle(Theme.Ink.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) { Kbd(key); Text(label) }
    }

    @ViewBuilder private var emptyState: some View {
        VStack(spacing: 10) {
            if !search.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 36)).foregroundStyle(Tone.green.solid)
                Text(filter == .unread ? "No unread notifications" : "Nothing here")
                    .textStyle(.toolbarTitle)
                    .foregroundStyle(Theme.Ink.primary)
                if filter != .all {
                    Button("Show All") { filter = .all }.buttonStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        if selectedThreads.count == 1, let ref = selectedThreads[0].ref {
            ThreadView(thread: selectedThreads[0], ref: ref, isSnoozing: snoozeBinding(selectedThreads[0].id))
                .id(selectedThreads[0].id)
        } else if selectedThreads.count == 1 {
            NotificationDetail(item: selectedThreads[0])
        } else {
            ContentUnavailableView("No Conversation Selected", systemImage: "tray",
                                   description: Text("Pick a notification to read it here."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Data

    /// Pull request authors by subject, for bot detection and `author:`.
    private var authors: [String: String] {
        Dictionary(state.pulls.map { (subjectKey($0.repo, $0.number), $0.author) }, uniquingKeysWith: { first, _ in first })
    }

    private var scopedThreads: [GitHubNotification] {
        state.notifications.filter { state.inScope($0.repo) }
    }

    private var visibleThreads: [GitHubNotification] {
        let query = JumpQuery(search)
        let authors = authors
        return scopedThreads
            .filter { filter.matches($0) || $0.id == selection }  // keep a just-read selection visible
            .filter { Inbox.matches($0, query, authors: authors) }
    }

    private var selectedThreads: [GitHubNotification] {
        state.notifications.filter { $0.id == selection }
    }

    // MARK: Actions

    private func select(_ id: String) {
        selection = id
        isListFocused = true
    }

    private func markAllRead(_ visible: [GitHubNotification]) {
        // Unread or All with no search is the whole inbox (or repository): one request covers it.
        let whole = (filter == .unread || filter == .all) && search.isEmpty
        state.markAllRead(visible, wholeInbox: whole)
    }

    private func move(_ delta: Int, in order: [String]) {
        guard !order.isEmpty else { return }
        let index = selection.flatMap(order.firstIndex) ?? -1
        selection = order[min(max(index + delta, 0), order.count - 1)]
    }

    private func commands(_ order: [String]) -> ListCommands {
        ListCommands(move: { move($0, in: order) },
                     done: { state.markDone(selectedThreads) },
                     snooze: { snoozing = selection },
                     mute: { state.mute(selectedThreads) })
    }

    private func handleKey(_ press: KeyPress, order: [String]) -> KeyPress.Result {
        guard !(NSApp.keyWindow?.firstResponder is NSTextView) else { return .ignored }
        func move(_ delta: Int) { self.move(delta, in: order) }
        switch press.key {
        case .downArrow: move(1); return .handled
        case .upArrow: move(-1); return .handled
        default: break
        }
        guard press.modifiers.isEmpty else { return .ignored }
        switch press.characters {
        case "j": move(1)
        case "k": move(-1)
        case "e": state.markDone(selectedThreads)
        case "s": snoozing = selection
        case "m": state.mute(selectedThreads)
        default: return .ignored
        }
        return .handled
    }

    private func snoozeBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { snoozing == id }, set: { snoozing = $0 ? id : nil })
    }
}

// MARK: - Rows

private struct NotificationRow: View {
    @Environment(AppState.self) private var state
    let thread: GitHubNotification
    let isSelected: Bool
    let authors: [String: String]
    @Binding var isSnoozing: Bool
    let select: () -> Void
    @State private var isHovered = false

    var body: some View {
        let tag = Inbox.tag(thread)
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(thread.unread ? Theme.accent : .clear)
                .frame(width: 7, height: 7)
                .padding(.top, 13)
                .accessibilityHidden(true)
            RepoSquare(repo: thread.repo, size: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(thread.title)
                    .textStyle(.rowTitle)
                    .fontWeight(thread.unread ? .semibold : .regular)
                    .foregroundStyle(Theme.Ink.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Chip(tag.text, tone: tag.tone, compact: true)
                    Text(meta).textStyle(.meta).foregroundStyle(Theme.Ink.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            ZStack(alignment: .topTrailing) {
                Text(Inbox.time(thread.updatedAt))
                    .textStyle(.meta)
                    .foregroundStyle(Theme.Ink.secondary)
                    .opacity(isHovered || isSelected || isSnoozing ? 0 : 1)
                if isHovered || isSelected || isSnoozing { quickActions }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(isSelected ? Theme.Selection.row : isHovered ? Theme.Fill.hover : .clear, in: .rect(cornerRadius: Theme.Radius.row))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.row).strokeBorder(isSelected ? Theme.Selection.rowStroke : .clear)
        }
        .contentShape(.rect)
        .onTapGesture(perform: select)
        .onHover { isHovered = $0 }
        .contextMenu {
            LinkActions(urls: [thread.webURL])
            Divider()
            NotificationActions(items: [thread])
            Button("Mute Thread", systemImage: "bell.slash") { state.mute([thread]) }
            Button("Add \(thread.repo) to Sidebar", systemImage: "sidebar.left") { state.addToSidebar(thread.repo) }
                .disabled(state.sidebarRepos.contains(thread.repo))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(thread.unread ? "Unread, " : "")\(thread.title), \(tag.text), \(meta)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(.default, select)
        .accessibilityAction(named: "Done") { state.markDone([thread]) }
        .accessibilityAction(named: "Mute thread") { state.mute([thread]) }
    }

    private var meta: String {
        let repo = thread.repo.split(separator: "/").last.map(String.init) ?? thread.repo
        let number = thread.ref.map { " #\($0.number)" } ?? ""
        let author = thread.subjectKey.flatMap { authors[$0] }.map { " · \($0)" } ?? ""
        return repo + number + author
    }

    /// Done, Snooze and Mute on a small raised capsule (I4).
    private var quickActions: some View {
        HStack(spacing: 0) {
            Button("Done", systemImage: "checkmark") { state.markDone([thread]) }.help("Done (E)")
            SnoozeIcon(isPresented: $isSnoozing) { state.snooze([thread], until: $0) }
            Button("Mute Thread", systemImage: "bell.slash") { state.mute([thread]) }.help("Mute thread (M)")
        }
        .buttonStyle(IconButtonStyle(diameter: 24))
        .font(.system(size: 12))
        .padding(2)
        .background(Theme.Surface.raised, in: .capsule)
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
    }
}

/// Snooze as an icon, with the same presets as the queue's Snooze button.
private struct SnoozeIcon: View {
    @Binding var isPresented: Bool
    let snooze: (Date) -> Void

    var body: some View {
        Button("Snooze", systemImage: "clock") { isPresented = true }
            .help("Snooze (S)")
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                SnoozeOptions { date in
                    isPresented = false
                    snooze(date)
                }
            }
    }
}

/// Several bot threads as one row (I5): count, repository spread, and Done with all.
private struct BotBundleRow: View {
    @Environment(AppState.self) private var state
    let threads: [GitHubNotification]
    let isExpanded: Bool
    let toggle: () -> Void
    @State private var isHovered = false

    var body: some View {
        let repos = Dictionary(grouping: threads, by: \.repo).sorted { $0.value.count > $1.value.count }
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(threads.contains(where: \.unread) ? Theme.accent : .clear).frame(width: 7, height: 7).padding(.top, 13)
            Image(systemName: "gearshape.2")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color(hex: 0x3A3A41), in: .rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 6) {
                Text("Bots · \(threads.count) updates").textStyle(.rowTitle).foregroundStyle(Theme.Ink.primary)
                HStack(spacing: 6) {
                    Chip("Bots", compact: true)
                    Text("bundled from \(repos.count) \(repos.count == 1 ? "repository" : "repositories")")
                        .textStyle(.meta).foregroundStyle(Theme.Ink.secondary)
                }
                HStack(spacing: 4) {
                    ForEach(repos.prefix(4), id: \.key) { repo, items in
                        Chip("\(repo.split(separator: "/").last ?? "") · \(items.count)", compact: true)
                    }
                }
                HStack {
                    Button(isExpanded ? "Collapse" : "Show all \(threads.count)") { toggle() }
                        .buttonStyle(.ghost).controlSize(.small)
                    Spacer()
                    Button("Done with all \(threads.count)") { state.markDone(threads) }
                        .buttonStyle(.secondary).controlSize(.small)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(isHovered ? Theme.Fill.hover : .clear, in: .rect(cornerRadius: Theme.Radius.row))
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(threads.count) bot updates")
    }
}

/// Mail's shortcuts: ⇧⌘U marks read, ⌃⌘A marks done.
struct NotificationActions: View {
    @Environment(AppState.self) private var state
    let items: [GitHubNotification]

    var body: some View {
        Button("Mark as Read", systemImage: "envelope.open") { state.markRead(items) }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .disabled(!items.contains(where: \.unread))
        Button("Mark as Done", systemImage: "checkmark") { state.markDone(items) }
            .keyboardShortcut("a", modifiers: [.command, .control])
            .disabled(items.isEmpty)
        Button("Mute Thread", systemImage: "bell.slash") { state.mute(items) }
            .disabled(items.isEmpty)
    }
}

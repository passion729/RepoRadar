import SwiftUI

/// The three pull request lists (P1), switched from the sidebar.
enum PullList: String, CaseIterable, Identifiable {
    case waiting, yours, mentioned

    var id: Self { self }

    var title: String {
        switch self {
        case .waiting: "Waiting on you"
        case .yours: "Yours"
        case .mentioned: "Mentioned"
        }
    }

    func matches(_ pull: PullItem) -> Bool {
        switch self {
        case .waiting: pull.roles.contains(.reviewRequested) && !pull.pr.isDraft
        case .yours: pull.roles.contains(.authored)
        // Assigned pull requests have no list of their own; they involve you the same way.
        case .mentioned: !pull.roles.contains(.authored) && (pull.roles.contains(.mentioned) || pull.roles.contains(.assigned))
        }
    }

    /// Waiting: direct requests before team ones, longest waiting first. The others: recently updated first.
    func sorted(_ pulls: [PullItem]) -> [PullItem] {
        switch self {
        case .waiting:
            pulls.sorted { ($0.isDirectReview ? 0 : 1, $0.pr.createdAt) < ($1.isDirectReview ? 0 : 1, $1.pr.createdAt) }
        case .yours, .mentioned:
            pulls.sorted { $0.updatedAt > $1.updatedAt }
        }
    }
}

/// Pull Requests (P1–P10): a 320 pt list and the pull request.
struct PullsView: View {
    @Environment(AppState.self) private var state
    let search: String
    let toolbar: StandardToolbar
    @SceneStorage("pullList") private var list: PullList = .waiting
    @SceneStorage("pullListWidth") private var listWidth = 320.0
    /// Each list keeps its own selection (P1).
    @State private var selections: [PullList: Int] = [:]
    @FocusState private var isListFocused: Bool

    private var selection: Int? { selections[list] }

    var body: some View {
        let items = visibleItems
        SplitPane(size: $listWidth, range: 280...480, minFlexible: 480) {
            VStack(spacing: 0) {
                if state.lastUpdated == nil && state.hasToken {
                    SkeletonRows(rowHeight: 72).padding(8)
                    Spacer()
                } else if items.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(items) { pull in
                                PullRow(pull: pull, list: list, isSelected: selection == pull.id) { select(pull.id) }
                            }
                        }
                        .padding(8)
                    }
                    .focusable()
                    .focused($isListFocused)
                    .focusEffectDisabled()
                    .onKeyPress(phases: .down) { handleKey($0, items: items) }
                }
                Rectangle().fill(Theme.separator).frame(height: 1)
                legend
            }
        } second: {
            if let pull = state.pulls.first(where: { $0.id == selection }) {
                PullDetailView(pull: pull).id(pull.id)
            } else {
                ContentUnavailableView("No Pull Request Selected", systemImage: "arrow.triangle.pull",
                                       description: Text("Pick one to see whether it can merge and who it's waiting on."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(list.title)
        .toolbar { toolbar }
        .focusedSceneValue(\.selectedURLs, state.pulls.filter { $0.id == selection }.map(\.pr.htmlUrl))
        .autoRead(selection, when: state.pulls.first { $0.id == selection }.map(state.needsAttention) ?? false) {
            state.markSeen(state.pulls.filter { $0.id == selection }.map(\.seenKey))
        }
        .onChange(of: state.requestedSelection, initial: true) {
            guard case .pull(let id)? = state.requestedSelection, let pull = state.pulls.first(where: { $0.id == id }) else { return }
            if !list.matches(pull) { list = PullList.allCases.first { $0.matches(pull) } ?? list }
            selections[list] = id
            state.requestedSelection = nil
        }
        .onChange(of: items.map(\.id), initial: true) { _, ids in
            // Merged or gone: select the next one so the detail never shows a stale pull request.
            if let selected = selections[list], !ids.contains(selected) { selections[list] = ids.first }
        }
    }

    private var visibleItems: [PullItem] {
        let query = JumpQuery(search)
        return list.sorted(state.pulls.filter { pull in
            state.inScope(pull.repo) && list.matches(pull)
                && (query.repo.map { pull.repo.localizedCaseInsensitiveContains($0) } ?? true)
                && (query.author.map { pull.author.localizedCaseInsensitiveContains($0) } ?? true)
                && (query.number.map { $0 == pull.number } ?? true)
                && query.words.allSatisfy { pull.title.localizedCaseInsensitiveContains($0) || pull.repo.localizedCaseInsensitiveContains($0) }
        })
    }

    private var legend: some View {
        let dots = HStack(spacing: 8) {
            HStack(spacing: 4) { Circle().fill(Tone.green.solid).frame(width: 7, height: 7); Text("checks") }
            HStack(spacing: 4) { Circle().fill(Tone.amber.solid).frame(width: 7, height: 7); Text("reviews") }
            HStack(spacing: 4) { Circle().strokeBorder(Theme.Ink.tertiary, lineWidth: 1.5).frame(width: 7, height: 7); Text("mergeable") }
        }
        .fixedSize()
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { dots; Text("in that order").foregroundStyle(Theme.Ink.tertiary).fixedSize(); Spacer(minLength: 0) }
            HStack { dots; Spacer(minLength: 0) }
        }
        .textStyle(.meta)
        .foregroundStyle(Theme.Ink.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var emptyState: some View {
        if !search.isEmpty {
            ContentUnavailableView.search(text: search)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 36)).foregroundStyle(Tone.green.solid)
                Text(list == .waiting ? "No reviews waiting on you" : "No pull requests here")
                    .textStyle(.toolbarTitle).foregroundStyle(Theme.Ink.primary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func select(_ id: Int) {
        selections[list] = id
        isListFocused = true
    }

    private func handleKey(_ press: KeyPress, items: [PullItem]) -> KeyPress.Result {
        guard !(NSApp.keyWindow?.firstResponder is NSTextView) else { return .ignored }
        func move(_ delta: Int) {
            let index = selection.flatMap { id in items.firstIndex { $0.id == id } } ?? -1
            selections[list] = items[min(max(index + delta, 0), items.count - 1)].id
        }
        switch press.key {
        case .downArrow: move(1); return .handled
        case .upArrow: move(-1); return .handled
        default: break
        }
        guard press.modifiers.isEmpty else { return .ignored }
        switch press.characters {
        case "j": move(1)
        case "k": move(-1)
        case "a":
            guard let pull = items.first(where: { $0.id == selection }), !pull.roles.contains(.authored) else { return .ignored }
            state.review(pull, .approve)
        default: return .ignored
        }
        return .handled
    }
}

/// The checks · reviews · mergeable dots (P2), with their words as the tooltip.
struct ReadinessDots: View {
    let status: PullStatus?

    var body: some View {
        let dots = Readiness.dots(status)
        HStack(spacing: 3) {
            ForEach(Array(dots.enumerated()), id: \.offset) { _, dot in
                if dot.state == .skipped {
                    Circle().strokeBorder(Theme.Ink.tertiary, lineWidth: 1.5).frame(width: 8, height: 8)
                } else {
                    Circle().fill(dot.state.color).frame(width: 8, height: 8)
                }
            }
        }
        .help(dots.map(\.text).joined(separator: " · "))
        .accessibilityElement()
        .accessibilityLabel(dots.map(\.text).joined(separator: ", "))
    }
}

private struct PullRow: View {
    @Environment(AppState.self) private var state
    let pull: PullItem
    let list: PullList
    let isSelected: Bool
    let select: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("\(pull.repo) #\(pull.number)").textStyle(.meta).foregroundStyle(Theme.Ink.secondary).lineLimit(1)
                Spacer(minLength: 6)
                Text(pull.pr.createdAt.shortAge()).textStyle(.meta).foregroundStyle(Theme.Ink.secondary)
            }
            Text(pull.title).textStyle(.rowTitle).foregroundStyle(Theme.Ink.primary).lineLimit(2)
            HStack(spacing: 6) {
                ReadinessDots(status: pull.status)
                if list == .yours, let tag = Readiness.yourTag(pull) {
                    Chip(tag.text, tone: tag.tone, compact: true)
                } else {
                    Text(blocker).textStyle(.meta).foregroundStyle(Theme.Ink.secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                if let status = pull.status, status.additions + status.deletions > 0 {
                    HStack(spacing: 4) {
                        Text("+\(status.additions)").foregroundStyle(Tone.green.text)
                        Text("−\(status.deletions)").foregroundStyle(Tone.red.text)
                    }
                    .font(.system(size: 11.5, design: .monospaced).monospacedDigit())
                }
            }
        }
        .padding(12)
        .background(isSelected ? Theme.Selection.row : isHovered ? Theme.Fill.hover : .clear, in: .rect(cornerRadius: Theme.Radius.row))
        .overlay { RoundedRectangle(cornerRadius: Theme.Radius.row).strokeBorder(isSelected ? Theme.Selection.rowStroke : .clear) }
        .contentShape(.rect)
        .onTapGesture(perform: select)
        .onHover { isHovered = $0 }
        .contextMenu {
            LinkActions(urls: [pull.pr.htmlUrl])
            Button("Pin \(pull.repo) to Sidebar", systemImage: "pin") { state.pin(pull.repo) }
                .disabled(state.pinnedRepos.contains(pull.repo) || state.pinnedRepos.count >= AppState.maxPins)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(.default, select)
    }

    /// What holds the pull request up, in a few words ("1 check running", "conflicts").
    private var blocker: String {
        Readiness.blockerText(pull.status)
    }
}

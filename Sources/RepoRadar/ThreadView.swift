import SwiftUI

/// One issue or pull request conversation (I6–I9): header, GitHub-style timeline, and a floating reply box.
struct ThreadView: View {
    @Environment(AppState.self) private var state
    let thread: GitHubNotification
    let ref: IssueRef
    @Binding var isSnoozing: Bool
    @State private var issue: IssueDetail?
    @State private var timeline: [TimelineEvent] = []
    @State private var canTriage = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Theme.separator).frame(height: 1)
            if let issue {
                conversation(issue)
            } else if let error {
                ContentUnavailableView("Couldn't Load", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                SkeletonRows(count: 3, rowHeight: 80).padding(20)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: "\(ref.repo)#\(ref.number)-\(state.timelineVersion)") { await load() }
    }

    // MARK: Header (I6)

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                RepoSquare(repo: ref.repo, size: 18)
                Text("\(ref.repo) · \(ref.isPullRequest ? "Pull request" : "Issue") #\(ref.number)")
                    .textStyle(.meta)
                    .foregroundStyle(Theme.Ink.secondary)
                    .lineLimit(1)
                Spacer()
                SnoozeButton(isPresented: $isSnoozing) { state.snooze([thread], until: $0) }
                Button("Mute thread") { state.mute([thread]) }
                    .buttonStyle(.secondary)
                    .help("Unsubscribe: new activity stays out of the Inbox")
                Button { state.markDone([thread]) } label: { HStack(spacing: 6) { Text("Done"); Kbd("E") } }
                    .buttonStyle(.primary)
                    .help("Done (E)")
                Button("Open on GitHub", systemImage: "arrow.up.right.square") { state.open([thread.webURL]) }
                    .buttonStyle(.icon)
                    .help("Open on GitHub (⌘O)")
            }
            Text(issue?.title ?? thread.title)
                .textStyle(.detailTitle)
                .foregroundStyle(Theme.Ink.primary)
                .textSelection(.enabled)
            if let issue {
                HStack(spacing: 6) {
                    Chip(issue.stateLabel, tone: stateTone(issue.stateLabel))
                    ForEach(issue.labels, id: \.name) { LabelChip(label: $0) }
                    Text(byline(issue)).textStyle(.meta).foregroundStyle(Theme.Ink.secondary).lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func byline(_ issue: IssueDetail) -> String {
        let participants = Set([issue.user.login] + timeline.filter { $0.event == "commented" }.map(\.who)).count
        let comments = issue.comments ?? timeline.count { $0.event == "commented" }
        return "opened \(issue.createdAt.formatted(.relative(presentation: .named))) by \(issue.user.login) · "
            + "\(comments) \(comments == 1 ? "comment" : "comments") · \(participants) \(participants == 1 ? "participant" : "participants")"
    }

    private func stateTone(_ label: String) -> Tone {
        switch label {
        case "Open": .green
        case "Merged": .purple
        case "Closed": .red
        default: .neutral
        }
    }

    // MARK: Timeline (I7)

    private func conversation(_ issue: IssueDetail) -> some View {
        let entries = ThreadEntry.build(issue: issue, timeline: timeline)
        let firstUnread = entries.first { entry in
            guard let date = entry.date, let lastRead = thread.lastReadAt else { return false }
            return date > lastRead && entry.isComment
        }?.id
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(entries) { entry in
                        ThreadEntryView(entry: entry, issueAuthor: issue.user.login, login: state.login)
                            .id(entry.id)
                    }
                }
                .background(alignment: .topLeading) {
                    // The 2 pt line joining the timeline, 16 pt in from the comment boxes' left edge.
                    Rectangle().fill(Theme.separator).frame(width: 2).padding(.leading, 32 + 10 + 15)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 180)  // room for the reply box
            }
            .overlay(alignment: .bottom) {
                ReplyBox(thread: thread, ref: ref,
                         canClose: !ref.isPullRequest && issue.state == "open" && canTriage)
            }
            .onAppear {
                if let firstUnread { proxy.scrollTo(firstUnread, anchor: .top) }
            }
        }
    }

    private func load() async {
        let client = GitHubClient.shared
        do {
            async let detail = client.issue(ref)
            async let events = client.timeline(ref)
            async let triage = try? client.canTriage(ref.repo)
            issue = try await detail
            timeline = (try? await events) ?? []
            canTriage = await triage ?? false
            error = nil
        } catch {
            self.error = (error as? GitHubError)?.message ?? error.localizedDescription
        }
    }
}

/// A row of the timeline: the opening post, a comment or review with a body, or a one-line event.
struct ThreadEntry: Identifiable, Hashable {
    enum Kind: Hashable {
        case comment(author: String, verb: String, body: String, association: String?)
        case event(TimelineEvent)
    }

    let id: String
    let kind: Kind
    let date: Date?

    var isComment: Bool { if case .comment = kind { true } else { false } }

    /// Events the timeline doesn't draw: subscriptions and bare mentions are noise.
    static let skipped: Set<String> = ["subscribed", "unsubscribed", "mentioned", "comment_deleted", "base_ref_changed"]

    static func build(issue: IssueDetail, timeline: [TimelineEvent]) -> [ThreadEntry] {
        var entries = [ThreadEntry(id: "opened", kind: .comment(author: issue.user.login,
                                                                verb: "opened this \(issue.pullRequest == nil ? "issue" : "pull request")",
                                                                body: issue.body ?? "", association: nil),
                                   date: issue.createdAt)]
        for (index, event) in timeline.enumerated() {
            guard let name = event.event, !skipped.contains(name) else { continue }
            let id = event.id.map { "e\($0)" } ?? "i\(index)"
            if name == "commented" || (name == "reviewed" && !(event.body ?? "").isEmpty) {
                let verb = name == "commented" ? "commented"
                    : event.state == "approved" ? "approved and commented"
                    : event.state == "changes_requested" ? "requested changes" : "reviewed"
                entries.append(ThreadEntry(id: id, kind: .comment(author: event.who, verb: verb, body: event.body ?? "",
                                                                  association: event.authorAssociation), date: event.date))
            } else {
                entries.append(ThreadEntry(id: id, kind: .event(event), date: event.date))
            }
        }
        return entries
    }
}

private struct ThreadEntryView: View {
    @Environment(AppState.self) private var state
    let entry: ThreadEntry
    let issueAuthor: String
    let login: String?

    var body: some View {
        switch entry.kind {
        case .comment(let author, let verb, let body, let association):
            CommentBox(author: author, verb: verb, text: body, date: entry.date,
                       badge: badge(author: author, association: association),
                       mentionsYou: login.map { body.localizedCaseInsensitiveContains("@\($0)") } ?? false)
        case .event(let event):
            EventRow(event: event)
        }
    }

    private func badge(author: String, association: String?) -> String? {
        if author == issueAuthor { return "Author" }
        return switch association {
        case "OWNER": "Owner"
        case "MEMBER": "Member"
        case "COLLABORATOR": "Collaborator"
        case "CONTRIBUTOR": "Contributor"
        default: nil
        }
    }
}

/// A comment: 32 pt avatar, a box with a title bar (author, time, badge) and the markdown body.
/// Comments that @-mention you get a purple outline.
private struct CommentBox: View {
    let author: String
    let verb: String
    let text: String
    let date: Date?
    let badge: String?
    let mentionsYou: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Avatar(login: author, size: 32)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(author).fontWeight(.semibold).foregroundStyle(Theme.Ink.primary)
                    Text(verb + (date.map { " " + $0.formatted(.relative(presentation: .named)) } ?? ""))
                        .foregroundStyle(Theme.Ink.secondary)
                    Spacer(minLength: 6)
                    if mentionsYou {
                        Chip("Mentioned you", tone: .purple, compact: true)
                    } else if let badge {
                        Chip(badge, compact: true)
                    }
                }
                .textStyle(.meta)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(mentionsYou ? Tone.purple.tint : Theme.Fill.subtle)
                Rectangle().fill(Theme.separator).frame(height: 1)
                Group {
                    if text.isEmpty {
                        Text("No description provided.").italic().foregroundStyle(Theme.Ink.tertiary)
                    } else {
                        MarkdownText(text).foregroundStyle(Theme.Ink.body)
                    }
                }
                .textStyle(.body)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.Surface.raised)
            .clipShape(.rect(cornerRadius: Theme.Radius.comment))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.comment)
                    .strokeBorder(mentionsYou ? Tone.purple.solid.opacity(0.45) : Theme.separator)
            }
            .background {
                if mentionsYou {
                    RoundedRectangle(cornerRadius: Theme.Radius.comment + 3).inset(by: -3).fill(Tone.purple.solid.opacity(0.1))
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// An event on the line: a 28 pt round icon and one sentence; a linked pull request also gets a card (I8).
private struct EventRow: View {
    @Environment(AppState.self) private var state
    let event: TimelineEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Ink.secondary)
                    .frame(width: 28, height: 28)
                    .background(Theme.Surface.raised, in: .circle)
                    .overlay { Circle().strokeBorder(Theme.Fill.subtle, lineWidth: 3) }
                    .padding(.leading, 32 + 10 + 16 - 14)  // centred on the line
                sentence
                    .textStyle(.meta)
                    .foregroundStyle(Theme.Ink.secondary)
                    .lineLimit(2)
            }
            if let source = event.source?.issue, source.pullRequest != nil {
                LinkedPullCard(source: source)
                    .padding(.leading, 32 + 10 + 16 + 14 + 10)
            }
        }
    }

    private var sentence: some View {
        let who = Text(event.who).fontWeight(.semibold).foregroundStyle(Theme.Ink.primary)
        let when = Text(event.date.map { " " + $0.formatted(.relative(presentation: .named)) } ?? "")
        let name = event.event ?? ""
        let what: Text = switch name {
        case "labeled": Text(" added the \(event.label?.name ?? "") label")
        case "unlabeled": Text(" removed the \(event.label?.name ?? "") label")
        case "cross-referenced":
            Text(event.source?.issue?.pullRequest != nil ? " linked a pull request" : " mentioned this in an issue")
        case "closed": Text(" closed this")
        case "reopened": Text(" reopened this")
        case "merged": Text(" merged this")
        case "review_requested": Text(" requested a review from \(event.requestedReviewer?.login ?? "a team")")
        case "reviewed": Text(event.state == "approved" ? " approved these changes" : event.state == "changes_requested" ? " requested changes" : " reviewed")
        case "committed": Text(" pushed “\(event.message?.split(separator: "\n").first.map(String.init) ?? "a commit")”")
        case "assigned": Text(" assigned \(event.assignee?.login ?? "someone")")
        case "unassigned": Text(" unassigned \(event.assignee?.login ?? "someone")")
        case "renamed": Text(" changed the title from “\(event.rename?.from ?? "")” to “\(event.rename?.to ?? "")”")
        case "head_ref_deleted": Text(" deleted the branch")
        case "head_ref_force_pushed": Text(" force-pushed the branch")
        case "ready_for_review": Text(" marked this ready for review")
        case "convert_to_draft": Text(" marked this as a draft")
        default: Text(" " + name.replacingOccurrences(of: "_", with: " "))
        }
        return Text("\(name == "committed" ? Text("") : who)\(what)\(when)")
    }

    private var symbol: String {
        switch event.event {
        case "labeled", "unlabeled": "tag"
        case "cross-referenced": "arrow.triangle.pull"
        case "closed": "xmark.circle"
        case "reopened": "arrow.uturn.left.circle"
        case "merged": "arrow.triangle.merge"
        case "review_requested": "eye"
        case "reviewed": "checkmark.bubble"
        case "committed", "head_ref_force_pushed": "circle.circle"
        case "assigned", "unassigned": "person"
        case "renamed": "pencil"
        case "head_ref_deleted": "trash"
        default: "ellipsis"
        }
    }
}

/// A pull request linked in the timeline (I8): its state, whether it waits on you, and Review now.
private struct LinkedPullCard: View {
    @Environment(AppState.self) private var state
    let source: TimelineEvent.Source.Issue

    var body: some View {
        let repo = source.repository?.fullName
        let pull = repo.flatMap { repo in state.pulls.first { $0.repo == repo && $0.number == source.number } }
        let waitsOnYou = pull?.roles.contains(.reviewRequested) == true
        HStack(spacing: 10) {
            StatusIcon(status(pull), size: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.title).textStyle(.rowTitle).foregroundStyle(Theme.Ink.primary).lineLimit(1)
                HStack(spacing: 0) {
                    Text([repo.map { "\($0.split(separator: "/").last ?? "") #\(source.number)" } ?? "#\(source.number)",
                          stateText(pull)].joined(separator: " · "))
                        .foregroundStyle(Theme.Ink.secondary)
                    if waitsOnYou {
                        Text(" · waiting on your review").fontWeight(.semibold).foregroundStyle(Tone.amber.text)
                    }
                }
                .textStyle(.meta)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let pull {
                Button(waitsOnYou ? "Review now" : "Open") { state.navigate(to: .pulls, select: .pull(pull.id)) }
                    .buttonStyle(waitsOnYou ? .primary : .secondary)
                    .controlSize(.small)
            } else {
                Button("Open on GitHub", systemImage: "arrow.up.right.square") { state.open([source.htmlUrl]) }
                    .buttonStyle(IconButtonStyle(diameter: 26))
            }
        }
        .padding(12)
        .background(Theme.Surface.raised, in: .rect(cornerRadius: Theme.Radius.comment))
        .overlay { RoundedRectangle(cornerRadius: Theme.Radius.comment).strokeBorder(Theme.separator) }
    }

    private func status(_ pull: PullItem?) -> StatusKind {
        if source.pullRequest?.mergedAt != nil { return .success }
        if source.state == "closed" { return .skipped }
        switch pull?.status?.checks {
        case .failing: return .failure
        case .pending: return .running
        case .passing: return .success
        default: return .waiting
        }
    }

    private func stateText(_ pull: PullItem?) -> String {
        if source.pullRequest?.mergedAt != nil { return "merged" }
        if source.state == "closed" { return "closed" }
        switch pull?.status?.checks {
        case .passing: return "checks passed"
        case .failing: return "checks failing"
        case .pending: return "checks running"
        default: return "open"
        }
    }
}

// MARK: - Reply box (I9)

/// Floating glass composer: markdown with formatting buttons, quick replies, Comment (⌘↵) and, for issues you
/// can triage, Comment and close. The draft is kept per thread.
private struct ReplyBox: View {
    @Environment(AppState.self) private var state
    let thread: GitHubNotification
    let ref: IssueRef
    let canClose: Bool
    @State private var selection: TextSelection?
    /// The editor's own text, synced with `state.drafts`: binding the editor to the shared dictionary
    /// reset its cursor while typing.
    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var draft: Binding<String> { $text }

    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: draft, selection: $selection)
                .textStyle(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 40, maxHeight: 140)
                .fixedSize(horizontal: false, vertical: true)
                .focused($isFocused)
                .overlay(alignment: .topLeading) {
                    if draft.wrappedValue.isEmpty {
                        Text("Reply to the thread… Markdown supported")
                            .textStyle(.body)
                            .foregroundStyle(Theme.Ink.tertiary)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.command) else { return .ignored }
                    send(close: false)
                    return .handled
                }
            HStack(spacing: 6) {
                Group {
                    Button("Bold", systemImage: "bold") { wrap("**", "**") }
                    Button("Italic", systemImage: "italic") { wrap("_", "_") }
                    Button("Code", systemImage: "chevron.left.forwardslash.chevron.right") { wrap("`", "`") }
                    Button("Link", systemImage: "link") { wrap("[", "](https://)") }
                }
                .buttonStyle(IconButtonStyle(diameter: 26))
                .font(.system(size: 12))
                ForEach(["+1", "Looking into it"], id: \.self) { quick in
                    Button(quick) { insert(quick) }.buttonStyle(.secondary).controlSize(.small)
                }
                Spacer(minLength: 6)
                if canClose {
                    Button("Comment and close") { send(close: true) }
                        .buttonStyle(.secondary)
                        .disabled(isEmpty)
                }
                Button { send(close: false) } label: { HStack(spacing: 6) { Text("Comment"); Kbd("⌘↵") } }
                    .buttonStyle(.primary)
                    .disabled(isEmpty)
                    .help("Comment (⌘↵)")
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .padding(14)
        .onAppear { text = state.drafts[thread.id] ?? "" }
        .onChange(of: text) { _, new in
            let value = new.isEmpty ? nil : new
            if state.drafts[thread.id] != value { state.drafts[thread.id] = value }
        }
        .onChange(of: state.drafts[thread.id]) { _, saved in
            // Sent (cleared) or brought back after GitHub refused it.
            if (saved ?? "") != text { text = saved ?? "" }
        }
    }

    private func send(close: Bool) {
        let body = draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        state.comment(on: ref, body: body, close: close, thread: thread)
    }

    /// Wraps the selection in markdown, or inserts the pair at the end.
    private func wrap(_ prefix: String, _ suffix: String) {
        var text = draft.wrappedValue
        if case .selection(let range)? = selection?.indices, range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex {
            let selected = text[range]
            text.replaceSubrange(range, with: prefix + selected + suffix)
        } else {
            text += prefix + suffix
        }
        draft.wrappedValue = text
        isFocused = true
    }

    private func insert(_ snippet: String) {
        let text = draft.wrappedValue
        draft.wrappedValue = text.isEmpty ? snippet : text + (text.hasSuffix(" ") || text.hasSuffix("\n") ? "" : " ") + snippet
        isFocused = true
    }
}

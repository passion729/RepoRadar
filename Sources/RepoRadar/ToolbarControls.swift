import SwiftUI

// The global toolbar buttons from the Now artboard: Filter repositories, Notification settings, Account.

// MARK: - Filter repositories (G7)

/// Which repositories RepoRadar watches: scope every page to one, pin it to the sidebar,
/// or leave a repository or a whole owner out of every list and count.
struct RepoFilterButton: View {
    @Environment(AppState.self) private var state
    @State private var isPresented = false

    var body: some View {
        Button("Filter Repositories", systemImage: "line.3.horizontal.decrease") { isPresented.toggle() }
            .symbolVariant(state.scopeRepo != nil || !state.excludedRepos.isEmpty || !state.excludedOwners.isEmpty ? .circle.fill : .none)
            .help("Filter repositories")
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                RepoFilterPopover { isPresented = false }
            }
    }
}

private struct RepoFilterPopover: View {
    @Environment(AppState.self) private var state
    let dismiss: () -> Void
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SearchField(prompt: "Filter repositories", text: $query, shortcut: nil)
                .padding(12)
            Rectangle().fill(Theme.separator).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if query.isEmpty {
                        ScopeRow(title: "All repositories", isSelected: state.scopeRepo == nil) {
                            state.scopeRepo = nil
                            dismiss()
                        }
                    }
                    ForEach(owners, id: \.self) { owner in
                        OwnerHeader(owner: owner)
                        if !state.excludedOwners.contains(owner) {
                            ForEach(repos(of: owner), id: \.self) { repo in
                                RepoFilterRow(repo: repo, dismiss: dismiss)
                            }
                        }
                    }
                    if owners.isEmpty {
                        Text(query.isEmpty ? "No repositories yet." : "No repositories match “\(query)”.")
                            .textStyle(.meta)
                            .foregroundStyle(Theme.Ink.tertiary)
                            .padding(10)
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 420)
            Rectangle().fill(Theme.separator).frame(height: 1)
            Text("Unchecked repositories are left out of every list, count and alert.")
                .textStyle(.meta)
                .foregroundStyle(Theme.Ink.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
        }
        .frame(width: 360)
    }

    /// Watched repositories plus excluded ones, so they can be brought back.
    private var allRepos: [String] {
        Set(state.repos + state.excludedRepos).filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var owners: [String] {
        let fromRepos = allRepos.map { String($0.prefix { $0 != "/" }) }
        let excluded = state.excludedOwners.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
        return Set(fromRepos + excluded).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func repos(of owner: String) -> [String] {
        allRepos.filter { $0.hasPrefix(owner + "/") }
    }
}

private struct ScopeRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).textStyle(.rowTitle).foregroundStyle(Theme.Ink.primary)
                Spacer()
                if isSelected { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct OwnerHeader: View {
    @Environment(AppState.self) private var state
    let owner: String

    var body: some View {
        let watched = Binding(get: { !state.excludedOwners.contains(owner) },
                              set: { state.setExcluded(owner: owner, !$0) })
        Toggle(isOn: watched) {
            Text(owner).textStyle(.label).foregroundStyle(Theme.Ink.tertiary)
        }
        .toggleStyle(.checkbox)
        .help(watched.wrappedValue ? "Stop watching every repository of \(owner)" : "Watch \(owner) again")
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }
}

private struct RepoFilterRow: View {
    @Environment(AppState.self) private var state
    let repo: String
    let dismiss: () -> Void
    @State private var isHovered = false

    var body: some View {
        let excluded = state.excludedRepos.contains(repo)
        let pinned = state.pinnedRepos.contains(repo)
        HStack(spacing: 8) {
            Toggle("Watch \(repo)", isOn: Binding(get: { !excluded }, set: { state.setExcluded(repo, !$0) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
            Button {
                state.scopeRepo = state.scopeRepo == repo ? nil : repo
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    RepoSquare(repo: repo)
                    Text(repo.split(separator: "/").last.map(String.init) ?? repo)
                        .textStyle(.rowTitle)
                        .fontWeight(.regular)
                        .foregroundStyle(excluded ? Theme.Ink.tertiary : Theme.Ink.primary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if state.scopeRepo == repo { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(excluded)
            .help(excluded ? "Not watched" : "Show only \(repo)")
            Button(pinned ? "Unpin" : "Pin to Sidebar", systemImage: pinned ? "pin.fill" : "pin") {
                pinned ? state.unpin(repo) : state.pin(repo)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(pinned ? Theme.accent : Theme.Ink.tertiary)
            .opacity(pinned || isHovered ? 1 : 0)
            .disabled(excluded || (!pinned && state.pinnedRepos.count >= AppState.maxPins))
            .help(pinned ? "Unpin from the sidebar" : "Pin to the sidebar")
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(isHovered ? Theme.Fill.hover : .clear, in: .rect(cornerRadius: 8))
        .onHover { isHovered = $0 }
    }
}

// MARK: - Notification settings

/// Which events pop up as system alerts, and a one-hour pause.
// ponytail: mirrors the current alert settings; phase 8 narrows them to G6's four cases.
struct AlertSettingsButton: View {
    @Environment(AppState.self) private var state
    @State private var isPresented = false

    var body: some View {
        Button("Notification Settings", systemImage: state.alertsPaused ? "bell.slash" : "bell") { isPresented.toggle() }
            .help(state.alertsPaused ? "Alerts paused" : "Notification settings")
            .popover(isPresented: $isPresented, arrowEdge: .bottom) { AlertSettingsPopover() }
    }
}

private struct AlertSettingsPopover: View {
    @Environment(AppState.self) private var state
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notifications").textStyle(.paneTitle)
            if state.alertsPaused, let until = state.alertsPausedUntil {
                HStack {
                    Label("Paused until \(until.formatted(date: .omitted, time: .shortened))", systemImage: "bell.slash")
                        .textStyle(.meta)
                        .foregroundStyle(Tone.amber.text)
                    Spacer()
                    Button("Resume") { state.resumeAlerts() }.buttonStyle(.secondary).controlSize(.small)
                }
            } else {
                Button("Pause Alerts for 1 Hour", systemImage: "bell.slash") { state.pauseAlerts(for: 3600) }
                    .buttonStyle(.secondary)
            }
            Rectangle().fill(Theme.separator).frame(height: 1)
            Text("Alert me when").textStyle(.label).foregroundStyle(Theme.Ink.tertiary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Alerts.Kind.allCases, id: \.self) { AlertToggle(kind: $0) }
            }
            .toggleStyle(.checkbox)
            .textStyle(.meta)
            Text("Everything else only updates the counts.").textStyle(.meta).foregroundStyle(Theme.Ink.tertiary)
            HStack {
                Spacer()
                SettingsLink { Text("More Settings…") }.buttonStyle(.ghost)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

/// One G6 alert kind's switch.
struct AlertToggle: View {
    let kind: Alerts.Kind
    @AppStorage private var isOn: Bool

    init(kind: Alerts.Kind) {
        self.kind = kind
        _isOn = AppStorage(wrappedValue: true, kind.setting)
    }

    var body: some View {
        Toggle(kind.title, isOn: $isOn)
    }
}

// MARK: - Account

/// The signed-in account: profile, settings and sign out.
struct AccountButton: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Menu {
            if let login = state.login {
                Text("Signed in as @\(login)")
                Button("Open Profile on GitHub", systemImage: "safari") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/\(login)")!)
                }
                Divider()
            }
            SettingsLink { Label("Settings…", systemImage: "gearshape") }
            if state.hasToken {
                Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { state.signOut() }
            }
        } label: {
            Avatar(login: state.login, size: 28)
        }
        .menuIndicator(.hidden)
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
        .help(state.login.map { "Account @\($0)" } ?? "Account")
        .accessibilityLabel(state.login.map { "Account @\($0)" } ?? "Account")
    }
}

/// A GitHub avatar, or the login's initial while it loads (or when signed out).
struct Avatar: View {
    let login: String?
    var size: CGFloat = 28

    var body: some View {
        AsyncImage(url: login.flatMap { URL(string: "https://github.com/\($0).png?size=\(Int(size * 2))") }) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Text(login?.prefix(1).uppercased() ?? "?")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(hex: 0x3B4A6B))
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .accessibilityHidden(true)
    }
}

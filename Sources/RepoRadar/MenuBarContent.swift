import SwiftUI

struct MenuBarContent: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let failing = state.latestRuns.filter { $0.state == .failure }.sorted { $0.createdAt > $1.createdAt }
        let reviews = state.pulls.filter { $0.roles.contains(.reviewRequested) }.sorted { $0.updatedAt > $1.updatedAt }
        let unread = state.notifications.filter(\.unread)

        Text("\(state.unreadCount) unread · \(state.reviewRequestCount) reviews · \(failing.count) failing")
        if let error = state.error {
            Text(error)
        }

        if !unread.isEmpty {
            Section("Unread") {
                ForEach(unread.prefix(5)) { item in
                    Button("\(item.repo) · \(item.title)") { state.open([item.webURL]) }
                }
            }
        }
        if !reviews.isEmpty {
            Section("Review Requests") {
                ForEach(reviews.prefix(5)) { item in
                    Button("\(item.repo) #\(item.pr.number) · \(item.title)") { state.open([item.pr.htmlUrl]) }
                }
            }
        }
        if !failing.isEmpty {
            Section("Failing Workflows") {
                ForEach(failing.prefix(5)) { run in
                    Button("\(run.repo) · \(run.workflowName)") { state.open([run.htmlUrl]) }
                }
            }
        }

        Divider()
        Button("Refresh Now") { Task { await state.refresh() } }
            .disabled(state.isRefreshing || !state.hasToken)
        Button("Open RepoRadar") {
            openWindow(id: "main")
            NSApp.activate()
        }
        SettingsLink { Text("Settings…") }
        Divider()
        Button("Quit RepoRadar") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

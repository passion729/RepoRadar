import SwiftUI

// Manual keys instead of `@Entry`: that macro's plugin (SwiftUIMacros) ships only with Xcode,
// and this project builds with the Command Line Tools.
private struct SelectedURLsKey: FocusedValueKey { typealias Value = [URL] }
private struct SelectedRunsKey: FocusedValueKey { typealias Value = [WorkflowRun] }
private struct SelectedNotificationsKey: FocusedValueKey { typealias Value = [GitHubNotification] }
private struct PageKey: FocusedValueKey { typealias Value = Binding<Page> }

extension FocusedValues {
    var selectedURLs: [URL]? {
        get { self[SelectedURLsKey.self] }
        set { self[SelectedURLsKey.self] = newValue }
    }

    var selectedRuns: [WorkflowRun]? {
        get { self[SelectedRunsKey.self] }
        set { self[SelectedRunsKey.self] = newValue }
    }

    var selectedNotifications: [GitHubNotification]? {
        get { self[SelectedNotificationsKey.self] }
        set { self[SelectedNotificationsKey.self] = newValue }
    }

    var page: Binding<Page>? {
        get { self[PageKey.self] }
        set { self[PageKey.self] = newValue }
    }
}

struct AppCommands: Commands {
    let state: AppState
    @FocusedValue(\.selectedURLs) private var selectedURLs
    @FocusedValue(\.selectedRuns) private var selectedRuns
    @FocusedValue(\.selectedNotifications) private var selectedNotifications
    @FocusedBinding(\.page) private var page
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        SidebarCommands()

        CommandGroup(replacing: .textEditing) {
            Button("Search or Jump To…") { SearchField.focusInKeyWindow() }
                .keyboardShortcut("k")
        }

        CommandGroup(after: .newItem) {
            LinkActions(urls: selectedURLs ?? [])
                .environment(state)
        }

        CommandGroup(before: .toolbar) {
            ForEach(Page.allCases) { item in
                Toggle(item.title, isOn: Binding(get: { page == item }, set: { _ in page = item }))
                    .keyboardShortcut(item.shortcut)
                    .disabled(page == nil)
            }
            Divider()
            Button("Refresh") { Task { await state.refresh() } }
                .keyboardShortcut("r")
                .disabled(state.isRefreshing || !state.hasToken)
            Divider()
        }

        CommandMenu("Notification") {
            NotificationActions(items: selectedNotifications ?? [])
                .environment(state)
        }

        CommandMenu("Run") {
            RunActions(runs: selectedRuns ?? [])
                .environment(state)
        }

        #if DEBUG
        CommandMenu("Debug") {
            Button("Component Gallery") { openWindow(id: "gallery") }
        }
        #endif
    }
}

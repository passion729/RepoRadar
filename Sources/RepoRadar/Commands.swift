import SwiftUI

// Manual keys instead of `@Entry`: that macro's plugin (SwiftUIMacros) ships only with Xcode,
// and this project builds with the Command Line Tools.
private struct SelectedURLsKey: FocusedValueKey { typealias Value = [URL] }
private struct SelectedRunsKey: FocusedValueKey { typealias Value = [WorkflowRun] }
private struct SelectedNotificationsKey: FocusedValueKey { typealias Value = [GitHubNotification] }
private struct SidebarSelectionKey: FocusedValueKey { typealias Value = Binding<SidebarItem?> }
private struct FocusTargetKey: FocusedValueKey { typealias Value = Binding<FocusTarget?> }

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

    var focusTarget: Binding<FocusTarget?>? {
        get { self[FocusTargetKey.self] }
        set { self[FocusTargetKey.self] = newValue }
    }

    var sidebarSelection: Binding<SidebarItem?>? {
        get { self[SidebarSelectionKey.self] }
        set { self[SidebarSelectionKey.self] = newValue }
    }
}

struct AppCommands: Commands {
    let state: AppState
    @FocusedValue(\.selectedURLs) private var selectedURLs
    @FocusedValue(\.selectedRuns) private var selectedRuns
    @FocusedValue(\.selectedNotifications) private var selectedNotifications
    @FocusedBinding(\.sidebarSelection) private var sidebarSelection
    @FocusedBinding(\.focusTarget) private var focusTarget
    @AppStorage("detailLayout") private var layout: DetailLayout = .bottom

    var body: some Commands {
        SidebarCommands()

        // Find focuses the in-content search row; ⇧⌘F filters the sidebar, as in Rockxy.
        CommandGroup(replacing: .textEditing) {
            Button("Find…") { focusTarget = .search }
                .keyboardShortcut("f")
            Button("Filter Sidebar") { focusTarget = .sidebarFilter }
                .keyboardShortcut("f", modifiers: [.command, .shift])
        }

        CommandGroup(after: .newItem) {
            LinkActions(urls: selectedURLs ?? [])
                .environment(state)
        }

        CommandGroup(before: .toolbar) {
            ForEach([SidebarItem.inbox, .pulls, .actions], id: \.self) { item in
                Toggle(item.title, isOn: Binding(get: { sidebarSelection == item }, set: { _ in sidebarSelection = item }))
                    .keyboardShortcut(item.shortcut)
            }
            Divider()
            Button("Refresh") { Task { await state.refresh() } }
                .keyboardShortcut("r")
                .disabled(state.isRefreshing || !state.hasToken)
            Divider()
            Picker("Detail Pane", selection: $layout) {
                Text("Below").tag(DetailLayout.bottom)
                Text("On the Right").tag(DetailLayout.right)
                Text("Hidden").tag(DetailLayout.hidden)
            }
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
    }
}

private extension SidebarItem {
    var shortcut: KeyEquivalent {
        switch self {
        case .inbox: "1"
        case .pulls: "2"
        default: "3"
        }
    }
}

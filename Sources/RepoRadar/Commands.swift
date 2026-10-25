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
    @FocusedBinding(\.inspector) private var inspector
    @FocusedValue(\.queueCommands) private var queue
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        SidebarCommands()

        // ⌘Z undoes the newest RepoRadar action while its undo window is open; otherwise it's the usual text undo.
        CommandGroup(replacing: .undoRedo) {
            Button(state.actions.canUndo ? "Undo Last Action" : "Undo") {
                if state.actions.canUndo {
                    state.actions.undoLast()
                } else {
                    NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                }
            }
            .keyboardShortcut("z")
            Button("Redo") { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .textEditing) {
            Button("Search or Jump To…") { SearchField.focusInKeyWindow() }
                .keyboardShortcut("k")
            Button("Find…") { SearchField.focusInKeyWindow() }
                .keyboardShortcut("f")
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
            Button(inspector == true ? "Hide Running and Health" : "Show Running and Health") { inspector?.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(inspector == nil)
            Divider()
            Button("Refresh") { Task { await state.refresh() } }
                .keyboardShortcut("r")
                .disabled(state.isRefreshing || !state.hasToken)
            Divider()
        }

        // The Now queue's keys. Single letters work only while the queue has focus (never in a text field).
        CommandMenu("Queue") {
            Group {
                Button("Next Item") { queue?.move(1) }.keyboardShortcut("j", modifiers: [])
                Button("Previous Item") { queue?.move(-1) }.keyboardShortcut("k", modifiers: [])
                Button("Expand or Collapse") { queue?.toggle() }.keyboardShortcut(.return, modifiers: [])
                Divider()
                Button("Approve") { queue?.primary() }.keyboardShortcut("a", modifiers: [])
                Button("Re-run Failed Jobs") { queue?.primary() }.keyboardShortcut("r", modifiers: [])
                Button("Squash and Merge") { queue?.merge() }.keyboardShortcut("m", modifiers: [.command, .shift])
                Divider()
                Button("Done") { queue?.done() }.keyboardShortcut("e", modifiers: [])
                Button("Snooze…") { queue?.snooze() }.keyboardShortcut("s", modifiers: [])
            }
            .disabled(queue == nil)
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

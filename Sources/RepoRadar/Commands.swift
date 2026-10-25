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
    @FocusedValue(\.listCommands) private var list
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        SidebarCommands()

        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { Updates.shared.check() }
                .disabled(!Updates.shared.isAvailable)
        }

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

        CommandGroup(before: .windowList) {
            Button("Open RepoRadar") { openWindow(id: "main") }
                .keyboardShortcut("0")
            Divider()
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

        // Every list's keys. Single letters work only while a list has focus (never in a text field).
        CommandMenu("List") {
            Button("Next Item") { list?.move(1) }.keyboardShortcut("j", modifiers: []).disabled(list == nil)
            Button("Previous Item") { list?.move(-1) }.keyboardShortcut("k", modifiers: []).disabled(list == nil)
            Button("Expand or Collapse") { list?.toggle?() }.keyboardShortcut(.return, modifiers: []).disabled(list?.toggle == nil)
            Divider()
            Button("Approve") { list?.primary?() }.keyboardShortcut("a", modifiers: []).disabled(list?.primary == nil)
            Button("Re-run Failed Jobs") { list?.primary?() }.keyboardShortcut("r", modifiers: []).disabled(list?.primary == nil)
            Button("Squash and Merge") { list?.merge?() }.keyboardShortcut("m", modifiers: [.command, .shift]).disabled(list?.merge == nil)
            Divider()
            Button("Done") { list?.done?() }.keyboardShortcut("e", modifiers: []).disabled(list?.done == nil)
            Button("Snooze…") { list?.snooze?() }.keyboardShortcut("s", modifiers: []).disabled(list?.snooze == nil)
            Button("Mute Thread") { list?.mute?() }.keyboardShortcut("m", modifiers: []).disabled(list?.mute == nil)
        }

        // Keep Debug builds within CommandsBuilder's ten-command limit.
        Group {
            CommandMenu("Notification") {
                NotificationActions(items: selectedNotifications ?? [])
                    .environment(state)
            }

            CommandMenu("Run") {
                RunActions(runs: selectedRuns ?? [])
                    .environment(state)
            }
        }

        #if DEBUG
        CommandMenu("Debug") {
            Button("Component Gallery") { openWindow(id: "gallery") }
            Button("Show Menu Bar Panel") { MenuBarController.shared?.toggle() }
        }
        #endif
    }
}

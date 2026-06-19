import SwiftUI

@main
struct RepoRadarApp: App {
    @StateObject private var state = AppState()
    @StateObject private var loc = Localizer.shared

    var body: some Scene {
        // Primary desktop window (also gives us a Dock icon).
        Window("RepoRadar", id: "main") {
            MainWindowView()
                .environmentObject(state)
                .environmentObject(loc)
                .environment(\.fontTheme, state.fontTheme)
                .frame(minWidth: 760, minHeight: 480)
                .task { state.bootstrap() }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button(loc(.refresh)) { Task { await state.refresh() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }

        // Always-on menu bar entry — GitHub mark octicon as the status icon.
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(state)
                .environmentObject(loc)
                .environment(\.fontTheme, state.menuFontTheme)
                .frame(width: 360)
        } label: {
            Image(nsImage: OcticonPath.templateImage(OcticonPath.markGithub, size: 16))
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(state)
                .environmentObject(loc)
                .environment(\.fontTheme, state.fontTheme)
        }
    }
}

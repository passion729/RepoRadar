import SwiftUI
import UserNotifications

@main
struct RepoRadarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var state = AppState.shared

    var body: some Scene {
        // A single dashboard window: it shows the whole account, so a second copy adds nothing.
        // `Window` also lets the menu bar extra bring it back with `openWindow(id:)`.
        Window("RepoRadar", id: "main") {
            MainView()
                .appliesFontTheme()
                .environment(state)
                .frame(minWidth: 960, minHeight: 480)
        }
        .defaultSize(width: 1320, height: 800)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands { AppCommands(state: state) }

        MenuBarExtra {
            MenuBarContent().environment(state)
        } label: {
            // Failures matter most, then unread notifications, then the overall Actions status.
            Image(systemName: state.failingCount > 0 ? RunState.failure.symbol
                  : state.unreadCount > 0 ? "bell.badge" : state.latestRuns.overall.map(\.symbol) ?? "bolt.horizontal.circle")
                .accessibilityLabel("RepoRadar")
        }

        Settings {
            SettingsView().environment(state).appliesFontTheme()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if Bundle.main.bundleIdentifier != nil { UNUserNotificationCenter.current().delegate = self }
        // `swift run` launches a bare binary; make it a regular foreground app.
        NSApp.setActivationPolicy(.regular)
        Task { @MainActor in AppState.shared.start() }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let url = (response.notification.request.content.userInfo["url"] as? String).flatMap(URL.init) {
            NSWorkspace.shared.open(url)
        }
    }
}

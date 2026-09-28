import SwiftUI
import UserNotifications

@main
struct RepoRadarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var state = AppState.shared

    var body: some Scene {
        // A single dashboard window: it shows the whole account, so a second copy adds nothing.
        // `Window` also lets the menu bar item bring it back with `openWindow(id:)`.
        Window("RepoRadar", id: "main") {
            MainView()
                .appliesFontTheme()
                .environment(state)
                .frame(minWidth: 960, minHeight: 480)
                .background(MenuBarWindowOpener())
        }
        .defaultSize(width: 1320, height: 800)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands { AppCommands(state: state) }

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
        Task { @MainActor in
            MenuBarController.shared = MenuBarController(state: AppState.shared)
            AppState.shared.start()
        }
    }

    /// Closing the window keeps RepoRadar running in the menu bar, like most Mac apps.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Clicking the Dock icon with no window open brings the main window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            Task { @MainActor in MenuBarController.shared?.show(nil) }
        }
        return true
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

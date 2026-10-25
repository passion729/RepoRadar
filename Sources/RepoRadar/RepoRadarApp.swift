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

        // A job's log on its own, beside the main window (A6).
        WindowGroup("Job Log", id: "job-log", for: JobLogRef.self) { $ref in
            if let ref {
                JobLogWindow(ref: ref).environment(state).appliesFontTheme().toasts(state.toasts)
            }
        }
        .restorationBehavior(.disabled)

        #if DEBUG
        Window("Component Gallery", id: "gallery") {
            ComponentGallery().appliesFontTheme()
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        #endif
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
            UNUserNotificationCenter.current().setNotificationCategories(Alerts.categories)
        }
        // `swift run` launches a bare binary; make it a regular foreground app.
        NSApp.setActivationPolicy(.regular)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] _ in
            self?.lastWindowClose = Date()
        }
        Task { @MainActor in
            MenuBarController.shared = MenuBarController(state: AppState.shared)
            AppState.shared.start()
            _ = Updates.shared  // starts Sparkle's daily check

        }
    }

    /// Closing the window keeps RepoRadar running in the menu bar, like most Mac apps.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// When a window last closed. SwiftUI can still end the app when its only `Window` scene closes,
    /// bypassing the delegate method above, so a termination right after a close is cancelled.
    private var lastWindowClose: Date = .distantPast

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Date().timeIntervalSince(lastWindowClose) < 1 ? .terminateCancel : .terminateNow
    }

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

    /// A click on an alert opens the item in RepoRadar; Re-run failed and Approve act without opening it.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let url = (info["url"] as? String).flatMap(URL.init)
        let item = (info["item"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let action = response.actionIdentifier
        await MainActor.run { AppState.shared.handleAlert(action: action, itemID: item, url: url) }
    }
}

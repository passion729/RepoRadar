import AppKit
import SwiftUI

/// Controls whether the app shows a Dock icon, following the main window and the
/// user's "keep Dock icon" preference.
///
/// Behaviour:
/// - While the main window is open, the Dock icon is always shown (`.regular`).
/// - When the main window is closed:
///   - if the user keeps the Dock icon (the default), it stays (`.regular`);
///   - otherwise the app becomes a menu-bar-only accessory (`.accessory`),
///     hiding the Dock icon and leaving just the menu bar item.
///
/// The activation policy is left untouched until the main window has been seen at
/// least once, so the app launches with its normal Dock icon regardless of the
/// stored preference.
@MainActor
final class DockVisibilityController {
    static let shared = DockVisibilityController()

    private var isMainWindowOpen = false
    private var keepDockIcon = true
    /// Avoid overriding the launch-time policy before the window is tracked.
    private var hasTrackedWindow = false

    private init() {}

    /// Updates the preference and re-applies the policy (only once the window
    /// has been tracked, to preserve the launch-time Dock icon).
    func setKeepDockIcon(_ keep: Bool) {
        keepDockIcon = keep
        if hasTrackedWindow { apply() }
    }

    func mainWindowDidOpen() {
        hasTrackedWindow = true
        isMainWindowOpen = true
        apply()
    }

    func mainWindowWillClose() {
        isMainWindowOpen = false
        // Defer so the policy change lands after the window is fully gone,
        // avoiding a flicker where AppKit briefly re-shows the Dock icon.
        DispatchQueue.main.async { [weak self] in self?.apply() }
    }

    private func apply() {
        let policy: NSApplication.ActivationPolicy =
            (keepDockIcon || isMainWindowOpen) ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        if policy == .regular {
            // Returning from accessory mode: bring the app forward so a freshly
            // reopened window actually gets focus.
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

/// Invisible bridge attached to the main window's content. Reports to
/// `DockVisibilityController` when the underlying `NSWindow` opens and closes so
/// the Dock icon can follow the window's lifecycle. Scoped to the main window
/// only — the menu bar popover never carries this view.
struct MainWindowDockBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { TrackingView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class TrackingView: NSView {
        private var closeObserver: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }

            DockVisibilityController.shared.mainWindowDidOpen()

            // Re-scope the close observer to whichever window we're now in
            // (a reopened main window is a fresh NSWindow instance).
            if let closeObserver {
                NotificationCenter.default.removeObserver(closeObserver)
            }
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    DockVisibilityController.shared.mainWindowWillClose()
                }
            }
        }

        deinit {
            if let closeObserver {
                NotificationCenter.default.removeObserver(closeObserver)
            }
        }
    }
}

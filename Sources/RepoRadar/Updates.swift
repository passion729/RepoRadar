import AppKit
import Observation
import Sparkle

/// Sparkle: checks `SUFeedURL` (appcast.xml on main) every hour, downloads updates in the background
/// and installs them, relaunching RepoRadar. Both can be turned off in Settings ▸ General.
/// Debug builds don't update: they would replace themselves with the release.
@MainActor @Observable
final class Updates {
    static let shared = Updates()

    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    /// Held here: Sparkle keeps only a weak reference.
    @ObservationIgnored private let delegate = InstallSoon()

    var automaticallyChecks: Bool {
        didSet { controller?.updater.automaticallyChecksForUpdates = automaticallyChecks }
    }

    var automaticallyInstalls: Bool {
        didSet { controller?.updater.automaticallyDownloadsUpdates = automaticallyInstalls }
    }

    var isAvailable: Bool { controller != nil }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        return info?["CFBundleVersion"].map { "\(short) (\($0))" } ?? short
    }

    private init() {
        #if DEBUG
        controller = nil
        #else
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: delegate, userDriverDelegate: nil)
        #endif
        automaticallyChecks = controller?.updater.automaticallyChecksForUpdates ?? false
        automaticallyInstalls = controller?.updater.automaticallyDownloadsUpdates ?? false
    }

    func check() { controller?.checkForUpdates(nil) }
}

/// Sparkle installs a downloaded update when the app quits, which a menu bar app rarely does. This installs it
/// and relaunches right away, or, while RepoRadar is frontmost, as soon as you switch to another app.
private final class InstallSoon: NSObject, SPUUpdaterDelegate {
    private var observer: NSObjectProtocol?

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock: @escaping () -> Void) -> Bool {
        MainActor.assumeIsolated {
            guard NSApp.isActive else { return immediateInstallationBlock() }
            observer = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                              object: nil, queue: .main) { _ in immediateInstallationBlock() }
        }
        return true
    }
}

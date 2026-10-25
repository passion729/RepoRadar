import Foundation
import Observation
import Sparkle

/// Sparkle: checks `SUFeedURL` (appcast.xml on main) once a day, downloads updates in the background
/// and installs them when RepoRadar quits. Both can be turned off in Settings ▸ General.
/// Debug builds don't update: they would replace themselves with the release.
@MainActor @Observable
final class Updates {
    static let shared = Updates()

    @ObservationIgnored private let controller: SPUStandardUpdaterController?

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
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        #endif
        automaticallyChecks = controller?.updater.automaticallyChecksForUpdates ?? false
        automaticallyInstalls = controller?.updater.automaticallyDownloadsUpdates ?? false
    }

    func check() { controller?.checkForUpdates(nil) }
}

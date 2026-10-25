import Foundation

/// Open product decisions (redesign spec §10), at their default values. Change them here.
enum Config {
    /// How long an inline action waits before it's sent to GitHub, and how long its toast offers Undo.
    /// Merging and approving deployments wait too.
    static let undoWindow: Duration = .seconds(4)
}

import Foundation

/// Optimistic actions with undo (G4). An action changes the interface at once, waits out the undo window,
/// and only then writes to GitHub. Undo inside the window sends nothing. If GitHub refuses, the change is
/// reverted and the toast shows GitHub's reason with Retry.
@MainActor @Observable
final class ActionQueue {
    private struct Pending {
        let revert: () -> Void
        let task: Task<Void, Never>
    }

    let toasts: ToastCenter
    private let window: Duration
    @ObservationIgnored private var pending: [UUID: Pending] = [:]
    /// The newest action still inside its undo window; ⌘Z undoes it.
    private(set) var undoable: UUID?

    init(toasts: ToastCenter, window: Duration = Config.undoWindow) {
        self.toasts = toasts
        self.window = window
    }

    var canUndo: Bool { undoable != nil }

    /// - Parameters:
    ///   - message: The toast, e.g. "Approved api-gateway #214".
    ///   - apply: The local change, made right away.
    ///   - revert: Undoes `apply`, on Undo or when GitHub refuses.
    ///   - commit: The write to GitHub, after the undo window.
    ///   - completed: Runs after a successful write (refresh the data it touched).
    ///   - failed: Runs after GitHub refused and `revert` ran (mark the row).
    func perform(_ message: String, apply: @escaping () -> Void, revert: @escaping () -> Void,
                 commit: @escaping () async throws -> Void, completed: (() async -> Void)? = nil,
                 failed: (() -> Void)? = nil) {
        apply()
        let id = UUID()
        toasts.show(message) { [weak self] in self?.undo(id) }
        schedule(id, delay: window, apply: apply, revert: revert, commit: commit, completed: completed, failed: failed)
    }

    func undo(_ id: UUID) {
        guard let action = pending.removeValue(forKey: id) else { return }
        action.task.cancel()
        action.revert()
        if undoable == id { undoable = nil }
        toasts.dismiss()
    }

    func undoLast() {
        if let undoable { undo(undoable) }
    }

    private func schedule(_ id: UUID, delay: Duration, apply: @escaping () -> Void, revert: @escaping () -> Void,
                          commit: @escaping () async throws -> Void, completed: (() async -> Void)?,
                          failed: (() -> Void)?) {
        let task = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }  // undone
            guard let self else { return }
            self.pending[id] = nil
            if self.undoable == id { self.undoable = nil }
            do {
                try await commit()
                await completed?()
            } catch {
                revert()
                failed?()
                let reason = (error as? GitHubError)?.message ?? error.localizedDescription
                self.toasts.showError(reason) { [weak self] in
                    // Retry goes straight to GitHub: the user has already seen the action and its undo.
                    guard let self else { return }
                    apply()
                    self.schedule(UUID(), delay: .zero, apply: apply, revert: revert, commit: commit, completed: completed, failed: failed)
                }
            }
        }
        pending[id] = Pending(revert: revert, task: task)
        if delay > .zero { undoable = id }
    }
}

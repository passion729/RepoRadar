import SwiftUI

extension View {
    /// Runs `action` once the selection has stayed put for the "autoReadSeconds" setting.
    /// Changing the selection cancels the timer.
    func autoRead<ID: Equatable>(_ selection: ID, when pending: Bool, _ action: @escaping () -> Void) -> some View {
        modifier(AutoRead(selection: selection, pending: pending, action: action))
    }
}

private struct AutoRead<ID: Equatable>: ViewModifier {
    @AppStorage("autoReadSeconds") private var seconds = 3
    let selection: ID
    let pending: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        content.task(id: selection) {
            guard seconds > 0, pending else { return }
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            action()
        }
    }
}

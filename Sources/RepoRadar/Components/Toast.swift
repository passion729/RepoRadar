import SwiftUI

/// Shows one toast at a time; a new one replaces the current one.
/// Confirmations offer Undo (⌘Z) and leave after `Config.undoWindow`; errors offer Retry and stay twice as long.
@MainActor @Observable
final class ToastCenter {
    struct Toast: Identifiable {
        struct Action {
            let title: String
            let shortcut: KeyEquivalent?
            let perform: () -> Void
        }

        let id = UUID()
        let message: String
        let isError: Bool
        let action: Action?
    }

    private(set) var current: Toast?
    @ObservationIgnored private var expiry: Task<Void, Never>?

    func show(_ message: String, undo: (() -> Void)? = nil) {
        present(Toast(message: message, isError: false,
                      action: undo.map { .init(title: "Undo", shortcut: "z", perform: $0) }))
    }

    func showError(_ message: String, retry: (() -> Void)? = nil) {
        present(Toast(message: message, isError: true,
                      action: retry.map { .init(title: "Retry", shortcut: nil, perform: $0) }))
    }

    func dismiss() {
        expiry?.cancel()
        current = nil
    }

    private func present(_ toast: Toast) {
        current = toast
        expiry?.cancel()
        let duration = toast.isError ? Config.undoWindow * 2 : Config.undoWindow
        expiry = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, self?.current?.id == toast.id else { return }
            self?.current = nil
        }
    }
}

extension View {
    /// Floats the center's toast at the bottom of this view.
    func toasts(_ center: ToastCenter) -> some View {
        modifier(ToastHost(center: center))
    }
}

private struct ToastHost: ViewModifier {
    let center: ToastCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast = center.current {
                ToastView(toast: toast) { center.dismiss() }
                    .id(toast.id)
                    .padding(.bottom, 20)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: center.current?.id)
    }
}

/// 44 pt dark glass capsule with white text.
struct ToastView: View {
    let toast: ToastCenter.Toast
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(toast.isError ? Tone.red.solid : Tone.green.solid)
                .accessibilityHidden(true)
            Text(toast.message)
                .textStyle(.button)
                .lineLimit(2)
                .foregroundStyle(.white)
            if let action = toast.action {
                Button {
                    dismiss()
                    action.perform()
                } label: {
                    HStack(spacing: 6) {
                        Text(action.title)
                        if action.shortcut != nil { Kbd("⌘Z") }
                    }
                }
                .buttonStyle(.secondary)
                .controlSize(.small)
                .modifier(OptionalShortcut(key: action.shortcut))
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, toast.action == nil ? 16 : 9)
        .frame(minHeight: 44)
        .glassEffect(.regular.tint(Color(30, 32, 38, 0.78)), in: .capsule)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isStaticText)
    }
}

private struct OptionalShortcut: ViewModifier {
    let key: KeyEquivalent?

    func body(content: Content) -> some View {
        if let key { content.keyboardShortcut(key) } else { content }
    }
}

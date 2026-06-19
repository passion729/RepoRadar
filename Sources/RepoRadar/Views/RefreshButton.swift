import SwiftUI

/// A refresh button whose icon spins continuously while a refresh is in flight.
/// The surrounding page is never covered — only this icon animates.
struct RefreshButton: View {
    let isRefreshing: Bool
    let action: () -> Void

    @State private var angle: Double = 0

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .rotationEffect(.degrees(angle))
        }
        .onAppear { sync(isRefreshing) }
        .onChange(of: isRefreshing) { _, refreshing in sync(refreshing) }
    }

    private func sync(_ refreshing: Bool) {
        if refreshing {
            withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                angle = 360
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) { angle = 0 }
        }
    }
}

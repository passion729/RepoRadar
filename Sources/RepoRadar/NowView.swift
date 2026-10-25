import SwiftUI

/// The Now page frame: an 80 pt status band over the queue (≥ 560) and a 420 pt right column.
// ponytail: layout only; the band, queue, Running now and Repository health (N5–N9) fill it in phase 4.
struct NowView: View {
    @Environment(AppState.self) private var state
    @SceneStorage("nowRightWidth") private var rightWidth = 420.0

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 80)
            Rectangle().fill(Theme.separator).frame(height: 1)
            SplitPane(sized: .second, size: $rightWidth, range: 320...520, minFlexible: 560) {
                column("Needs you")
            } second: {
                column("Running now")
            }
        }
    }

    private func column(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).textStyle(.paneTitle).foregroundStyle(Theme.Ink.primary)
            SkeletonRows(count: state.lastUpdated == nil ? 6 : 2)
        }
        .padding(Theme.Space.pane)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

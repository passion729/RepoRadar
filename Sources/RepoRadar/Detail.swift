import SwiftUI

/// Threads without an issue page: CI threads open their workflow run; releases, discussions and the rest show
/// what the notification says and a link.
struct NotificationDetail: View {
    @Environment(AppState.self) private var state
    let item: GitHubNotification
    @State private var run: WorkflowRun?
    @State private var isResolving = false

    var body: some View {
        // Not Group: Group applies .task to each child, restarting it on every state switch.
        ZStack(alignment: .top) {
            if let run {
                RunDetailView(run: run)
            } else if isResolving {
                SkeletonRows(count: 3, rowHeight: 44).padding(20).frame(maxHeight: .infinity, alignment: .top)
            } else {
                summary
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: item) {
            run = nil
            guard item.workflowRunHint != nil else { return }
            isResolving = true
            run = try? await GitHubClient.shared.run(for: item)
            isResolving = false
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                RepoSquare(repo: item.repo, size: 18)
                Text("\(item.repo) · \(item.typeLabel)").textStyle(.meta).foregroundStyle(Theme.Ink.secondary)
                Spacer()
                Button("Open on GitHub", systemImage: "arrow.up.right.square") { state.open([item.webURL]) }
                    .buttonStyle(.icon)
            }
            Text(item.title).textStyle(.detailTitle).foregroundStyle(Theme.Ink.primary).textSelection(.enabled)
            HStack(spacing: 8) {
                let tag = Inbox.tag(item)
                Chip(tag.text, tone: tag.tone)
                Text("updated \(item.updatedAt.formatted(.relative(presentation: .named)))")
                    .textStyle(.meta).foregroundStyle(Theme.Ink.secondary)
            }
            Button("Open on GitHub") { state.open([item.webURL]) }.buttonStyle(.primary)
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

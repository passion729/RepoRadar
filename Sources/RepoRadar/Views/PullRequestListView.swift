import SwiftUI

struct PullRequestListView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var loc: Localizer
    let repo: Repository
    @Environment(\.openURL) private var openURL

    private var prs: [PullRequest] {
        state.pullRequestsByRepo[repo.fullName] ?? []
    }

    var body: some View {
        Group {
            if prs.isEmpty {
                ContentUnavailableView(
                    loc(.prListEmptyTitle),
                    systemImage: "arrow.triangle.pull",
                    description: Text(repo.fullName)
                )
            } else {
                List(prs) { pr in
                    PullRequestRow(pr: pr)
                }
            }
        }
        .navigationTitle(repo.fullName)
        .toolbar {
            ToolbarItem {
                Button {
                    openURL(repo.webURL)
                } label: {
                    Image(systemName: "safari")
                }
                .help(loc(.openRepoInBrowser))
            }
        }
    }
}

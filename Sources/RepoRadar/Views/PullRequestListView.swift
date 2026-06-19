import SwiftUI

/// A single repo's PRs, grouped by status via a top tab (Open / Merged /
/// Closed). Open shows all; Merged/Closed are limited to the last month.
/// Data is cached per repo in AppState, so switching repos is instant and a
/// late fetch can't land under the wrong repo.
struct PullRequestListView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var loc: Localizer
    let repo: Repository

    @State private var tab: PRState = .open

    private static let tabs: [PRState] = [.open, .merged, .closed]

    private var prs: [PullRequest] { state.repoDetailPRs[repo.fullName] ?? [] }
    private var isLoading: Bool { state.loadingRepoDetail.contains(repo.fullName) }

    private func items(_ status: PRState) -> [PullRequest] {
        prs.filter { $0.prState == status }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Self.tabs, id: \.self) { status in
                    Text("\(loc(status.labelKey)) (\(items(status).count))").tag(status)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(8)

            Divider()

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle(repo.fullName)
        .task(id: repo.fullName) {
            tab = .open
            await state.loadRepoDetail(repo)
        }
    }

    @ViewBuilder
    private var content: some View {
        let list = items(tab)
        if list.isEmpty {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    loc(.prListEmptyTitle),
                    systemImage: "arrow.triangle.pull",
                    description: Text(repo.fullName)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            List(list) { pr in
                PullRequestRow(pr: pr)
            }
        }
    }
}

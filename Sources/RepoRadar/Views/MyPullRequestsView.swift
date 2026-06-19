import SwiftUI

/// Aggregate view of every PR related to the logged-in user — authored,
/// assigned, review-requested, or mentioned — grouped by status
/// (Open → Merged → Closed). The owning repo is shown on each row.
struct MyPullRequestsView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var loc: Localizer

    var body: some View {
        Group {
            if state.myPullRequests.isEmpty {
                ContentUnavailableView(
                    loc(.relatedPRsEmptyTitle),
                    systemImage: "arrow.triangle.pull",
                    description: Text(loc(.relatedPRsEmptyDesc))
                )
            } else {
                List {
                    ForEach(state.myPullRequestsByStatus, id: \.state) { group in
                        Section {
                            ForEach(group.prs) { item in
                                PullRequestRow(pr: item.pr, relations: item.relations, showRepo: true)
                            }
                        } header: {
                            HStack {
                                Text(loc(group.state.labelKey))
                                Spacer()
                                Text("\(group.prs.count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(loc(.relatedPRsTitle(state.totalMyPRs)))
    }
}

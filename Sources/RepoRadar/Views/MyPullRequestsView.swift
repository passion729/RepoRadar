import SwiftUI

/// Aggregate view of PRs related to the logged-in user — authored, assigned,
/// review-requested, or mentioned. A top tab switches status (Open / Merged /
/// Closed). Loads the last week by default and pages in more on scroll.
struct MyPullRequestsView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var loc: Localizer
    @State private var tab: PRState = .open

    private static let tabs: [PRState] = [.open, .merged, .closed]

    private var items: [RelatedPullRequest] {
        state.myPullRequests(in: tab)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Self.tabs, id: \.self) { status in
                    Text("\(loc(status.labelKey)) (\(state.myPRsCount(in: status)))").tag(status)
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
        .navigationTitle(loc(.relatedPRsTitle(state.totalMyPRs)))
        .task {
            if state.myPullRequests.isEmpty && !state.isLoadingMyPRs {
                await state.loadRelatedPRs()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if items.isEmpty {
            if state.isLoadingMyPRs {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    loc(.relatedPRsEmptyTitle),
                    systemImage: "arrow.triangle.pull",
                    description: Text(loc(.relatedPRsEmptyDesc))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            List {
                ForEach(items) { item in
                    PullRequestRow(pr: item.pr, relations: item.relations, showRepo: true)
                }
            }
        }
    }
}

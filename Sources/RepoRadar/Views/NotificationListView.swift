import SwiftUI

struct NotificationListView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var loc: Localizer

    var body: some View {
        Group {
            if state.notifications.isEmpty {
                ContentUnavailableView(
                    loc(.notificationsEmptyTitle),
                    systemImage: "bell.slash",
                    description: Text(loc(.notificationsEmptyDesc))
                )
            } else {
                List {
                    ForEach(state.notificationsByRepo, id: \.repo) { group in
                        Section {
                            ForEach(group.items) { item in
                                NotificationRow(notification: item)
                            }
                        } header: {
                            HStack {
                                Text(group.repo)
                                Spacer()
                                let unread = group.items.filter(\.unread).count
                                if unread > 0 {
                                    Text(loc(.unreadCount(unread)))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(loc(.notificationsTitle(state.unreadNotifications)))
    }
}

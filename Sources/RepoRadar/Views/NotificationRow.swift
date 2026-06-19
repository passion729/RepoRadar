import SwiftUI

struct NotificationRow: View {
    let notification: GitHubNotification
    @Environment(\.fontTheme) private var theme
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(notification.webURL)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(notification.unread ? Color.accentColor : Color.clear)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(notification.subject.title)
                        .font(theme.ui(.subheadline))
                        .lineLimit(2)
                    Text("\(notification.repository.fullName) · \(notification.subject.type)")
                        .font(theme.ui(.caption))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }
}

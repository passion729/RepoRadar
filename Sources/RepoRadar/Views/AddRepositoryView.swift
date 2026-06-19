import SwiftUI

struct AddRepositoryView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var loc: Localizer
    @Environment(\.fontTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var input = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(loc(.addRepoTitle))
                .font(theme.ui(.title2, weight: .bold))
            Text(loc(.addRepoSubtitle))
                .font(theme.ui(.caption))
                .foregroundStyle(.secondary)

            TextField(loc(.addRepoPlaceholder), text: $input)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
                .disabled(busy)

            if let error {
                Text(error)
                    .font(theme.ui(.caption))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button(loc(.cancel)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(loc(.add)) { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || busy)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func submit() {
        guard !busy else { return }
        busy = true
        error = nil
        Task {
            let ok = await state.addRepository(input)
            busy = false
            if ok {
                dismiss()
            } else {
                error = state.lastError
            }
        }
    }
}

import SwiftUI

struct AddRepositoryView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var loc: Localizer
    @Environment(\.fontTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var input = ""
    @State private var busy = false
    @State private var error: String?
    @State private var myRepos: [String] = []
    @State private var loadingRepos = false

    private var alreadyAdded: Set<String> {
        Set(state.repositories.map(\.fullName))
    }

    /// Owned repos matching the query (or the most recent ones when empty),
    /// excluding repos already being monitored.
    private var suggestions: [String] {
        let query = input.trimmingCharacters(in: .whitespaces).lowercased()
        let pool = myRepos.filter { !alreadyAdded.contains($0) }
        let matched = query.isEmpty ? pool : pool.filter { $0.lowercased().contains(query) }
        return Array(matched.prefix(50))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(loc(.addRepoTitle))
                .font(theme.ui(.title2, weight: .bold))
            Text(loc(.addRepoSubtitle))
                .font(theme.ui(.caption))
                .foregroundStyle(.secondary)

            TextField(loc(.addRepoPlaceholder), text: $input)
                .textFieldStyle(.roundedBorder)
                .onSubmit { attemptAdd(input) }
                .disabled(busy)

            repoSuggestions
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

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
                Button(loc(.add)) { attemptAdd(input) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || busy)
            }
        }
        .padding(20)
        .frame(width: 420, height: 460)
        .task {
            guard myRepos.isEmpty else { return }
            loadingRepos = true
            myRepos = (try? await GitHubClient.shared.myRepositories()) ?? []
            loadingRepos = false
        }
    }

    @ViewBuilder
    private var repoSuggestions: some View {
        if loadingRepos {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(loc(.addRepoLoadingRepos))
                    .font(theme.ui(.caption))
                    .foregroundStyle(.secondary)
            }
        } else if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(loc(.addRepoYourRepos))
                    .font(theme.ui(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(suggestions, id: \.self) { name in
                            Button { attemptAdd(name) } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "folder")
                                        .foregroundStyle(.secondary)
                                    Text(name).font(theme.ui(.subheadline))
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                                .padding(.vertical, 5)
                                .padding(.horizontal, 6)
                            }
                            .buttonStyle(.plain)
                            .disabled(busy)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.quaternary)
                )
            }
        }
    }

    private func attemptAdd(_ raw: String) {
        let name = raw.trimmingCharacters(in: .whitespaces)
        guard !busy, !name.isEmpty else { return }
        busy = true
        error = nil
        Task {
            let ok = await state.addRepository(name)
            busy = false
            if ok {
                dismiss()
            } else {
                error = state.lastError
            }
        }
    }
}

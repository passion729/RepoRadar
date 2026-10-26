import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Account", systemImage: "person.crop.circle") { AccountSettings() }
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Appearance", systemImage: "textformat.size") { AppearanceSettings() }
        }
        .frame(width: 500)
    }
}

struct AccountSettings: View {
    @Environment(AppState.self) private var state
    @State private var token = ""
    @State private var deviceCode: DeviceCode?
    @State private var loginTask: Task<Void, Never>?
    @State private var loginError: String?
    /// The GitHub CLI's signed-in account, when there is one.
    @State private var cliAccount: String?

    var body: some View {
        Form {
            if let deviceCode {
                Section("Authorize in your browser") {
                    LabeledContent("Device code") {
                        Text(deviceCode.userCode)
                            .themeFont(.title2, mono: true, weight: .semibold)
                            .textSelection(.enabled)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .glassEffect(.regular.tint(.accentColor.opacity(0.2)), in: .capsule)
                    }
                    Text("The code is on your clipboard. Paste it at \(deviceCode.verificationUri.absoluteString) and approve RepoRadar.")
                        .foregroundStyle(.secondary)
                    Button("Cancel") { loginTask?.cancel() }
                        .keyboardShortcut(.cancelAction)
                }
            } else if state.hasToken {
                Section {
                    LabeledContent("Signed in as", value: state.login.map { "@\($0)" } ?? "…")
                    if state.usesGitHubCLI {
                        LabeledContent("Account from", value: "GitHub CLI (gh)")
                    }
                    if let scopes = state.tokenScopes {
                        LabeledContent("Permissions", value: scopes.isEmpty ? "—" : scopes.sorted().joined(separator: ", "))
                    }
                    Button("Sign Out") { state.signOut() }
                } footer: {
                    if state.usesGitHubCLI {
                        Text("RepoRadar asks gh for its token as needed. Signing out here leaves gh signed in.")
                    }
                }
                if !state.usesGitHubCLI, let cliAccount {
                    Section {
                        Button("Use GitHub CLI Account (@\(cliAccount)) Instead") { useCLI() }
                    }
                }
                if !state.usesGitHubCLI, let scopes = state.tokenScopes, !scopes.contains("read:org"), !scopes.contains("admin:org") {
                    Section {
                        Button("Re-authorize with GitHub…") { startDeviceFlow() }
                    } footer: {
                        Text("This token can't read organization teams, so team reviewers are looked up one request at a time. Re-authorizing adds read:org (read-only). A personal access token needs read:org added on GitHub.")
                    }
                }
            } else {
                if let cliAccount {
                    Section {
                        Button("Use GitHub CLI Account (@\(cliAccount))") { useCLI() }
                            .buttonStyle(.glassProminent)
                    } footer: {
                        Text("You're signed in to the GitHub CLI (gh). RepoRadar uses that login and follows it if it changes.")
                    }
                }
                Section {
                    if cliAccount == nil {
                        Button("Sign in with GitHub…") { startDeviceFlow() }.buttonStyle(.glassProminent)
                    } else {
                        Button("Sign in with GitHub…") { startDeviceFlow() }
                    }
                } footer: {
                    Text("Opens github.com to approve access. No password is stored.")
                }
                Section {
                    SecureField("Token", text: $token, prompt: Text("ghp_…"))
                    Button("Save Token") {
                        state.signIn(token: token.trimmingCharacters(in: .whitespacesAndNewlines))
                        token = ""
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("Personal access token")
                } footer: {
                    Text("Needs the repo, notifications and read:org scopes.")
                }
            }
            if let loginError {
                Text(loginError).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .task(id: state.hasToken) { cliAccount = await GitHubCLI.account() }
    }

    private func useCLI() {
        loginError = nil
        Task {
            if !(await state.signInWithGitHubCLI()) {
                loginError = "The GitHub CLI didn't hand over a token. Run `gh auth login` in Terminal and try again."
            }
        }
    }

    private func startDeviceFlow() {
        loginError = nil
        loginTask = Task {
            defer { deviceCode = nil }
            do {
                let code = try await DeviceFlow.requestCode()
                deviceCode = code
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code.userCode, forType: .string)
                NSWorkspace.shared.open(code.verificationUri)
                state.signIn(token: try await DeviceFlow.poll(code))
            } catch is CancellationError {
            } catch {
                loginError = error.localizedDescription
            }
        }
    }
}

struct GeneralSettings: View {
    @Environment(AppState.self) private var state
    @AppStorage("refreshMinutes") private var refreshMinutes = 5
    @AppStorage("lookbackDays") private var lookbackDays = 30
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("autoReadSeconds") private var autoReadSeconds = 3
    @AppStorage("doneAfterReply") private var doneAfterReply = true
    @Bindable private var updates = Updates.shared

    var body: some View {
        Form {
            Section {
                Picker("Refresh every", selection: $refreshMinutes) {
                    ForEach([1, 2, 5, 10, 15, 30, 60], id: \.self) { Text("\($0) min").tag($0) }
                }
                Picker("Watch repositories pushed within", selection: $lookbackDays) {
                    ForEach([7, 14, 30, 90, 365], id: \.self) { Text("\($0) days").tag($0) }
                }
            } footer: {
                Text("Includes repositories you own, collaborate on, or can access through an organization. Archived repositories are skipped.")
            }
            Section {
                ForEach(state.excludedOwners, id: \.self) { owner in
                    LabeledContent("\(owner) (all repositories)") {
                        Button("Watch Again") { state.setExcluded(owner: owner, false) }
                    }
                }
                ForEach(state.excludedRepos, id: \.self) { repo in
                    LabeledContent(repo) {
                        Button("Watch Again") { state.setExcluded(repo, false) }
                    }
                }
                if state.excludedRepos.isEmpty && state.excludedOwners.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                }
            } header: {
                Text("Excluded repositories")
            } footer: {
                Text("Exclude repositories or whole organizations from the Filter Repositories button in the toolbar.")
            }
            Section {
                ForEach(Alerts.Kind.allCases, id: \.self) { AlertToggle(kind: $0) }
            } header: {
                Text("Alert me when")
            } footer: {
                Text("Everything else only updates the counts. The Dock badge counts what needs you.")
            }
            Section {
                Toggle("Show RepoRadar in the menu bar", isOn: $showMenuBarIcon)
            }
            Section {
                Picker("Mark as read after viewing", selection: $autoReadSeconds) {
                    Text("Never").tag(0)
                    ForEach([1, 2, 3, 5, 10, 30], id: \.self) { Text("\($0) sec").tag($0) }
                }
                Toggle("Mark a thread done after replying to it", isOn: $doneAfterReply)
            } footer: {
                Text("Read notifications, and failing workflows or review requests you've viewed, stop counting toward the badges until something new happens.")
            }
            Section {
                Toggle("Check for updates automatically", isOn: $updates.automaticallyChecks)
                Toggle("Download and install updates automatically", isOn: $updates.automaticallyInstalls)
                    .disabled(!updates.automaticallyChecks)
                LabeledContent("Version \(Updates.version)") {
                    Button("Check Now") { updates.check() }
                }
            } header: {
                Text("Updates")
            } footer: {
                Text(updates.isAvailable
                     ? "RepoRadar checks once a day. Updates download in the background, then RepoRadar restarts to install them once you switch to another app."
                     : "Updates are off in debug builds.")
            }
            .disabled(!updates.isAvailable)
        }
        .formStyle(.grouped)
        .onChange(of: refreshMinutes) { if state.hasToken { state.start() } }
        .onChange(of: lookbackDays) { Task { await state.refresh() } }
    }
}

struct AppearanceSettings: View {
    @AppStorage("fontFamily") private var family = ""
    @AppStorage("monoFontFamily") private var monoFamily = ""
    @AppStorage("fontSize") private var size = 13.0
    @Environment(\.fontTheme) private var theme

    var body: some View {
        Form {
            Section {
                Picker("Font", selection: $family) {
                    Text("System").tag("")
                    Divider()
                    ForEach(FontCatalog.families, id: \.self) { Text($0).tag($0) }
                }
                Picker("Monospaced font", selection: $monoFamily) {
                    Text("System Monospaced").tag("")
                    Divider()
                    ForEach(FontCatalog.monoFamilies, id: \.self) { Text($0).tag($0) }
                }
                LabeledContent("Size") {
                    HStack {
                        Slider(value: $size, in: 10...20, step: 1)
                        Stepper("\(Int(size)) pt", value: $size, in: 10...20)
                            .monospacedDigit()
                            .fixedSize()
                    }
                }
            } footer: {
                Text("Applies to the main window right away. The monospaced font is used for branches, code and SHAs.")
            }
            Section("Preview") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CI workflow run failed for main").themeFont(.headline)
                    Text("octocat/hello-world · 2 min ago").themeFont(.callout).foregroundStyle(.secondary)
                    Text("feature/improve-dependency-graph").themeFont(.body, mono: true)
                }
            }
            Section {
                Button("Restore Defaults") {
                    family = ""
                    monoFamily = ""
                    size = 13
                }
                .disabled(family.isEmpty && monoFamily.isEmpty && size == 13)
            }
        }
        .formStyle(.grouped)
    }
}

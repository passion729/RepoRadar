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

    var body: some View {
        Form {
            if state.hasToken {
                Section {
                    LabeledContent("Signed in as", value: state.login.map { "@\($0)" } ?? "…")
                    Button("Sign Out") { state.signOut() }
                }
            } else if let deviceCode {
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
            } else {
                Section {
                    Button("Sign in with GitHub…") { startDeviceFlow() }
                        .buttonStyle(.glassProminent)
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
                    Text("Needs the repo and notifications scopes.")
                }
            }
            if let loginError {
                Text(loginError).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
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
    @AppStorage("notifyFailures") private var notifyFailures = true
    @AppStorage("notifyFinishedRuns") private var notifyFinishedRuns = true
    @AppStorage("notifyStartedRuns") private var notifyStartedRuns = true
    @AppStorage("notifyInbox") private var notifyInbox = true
    @AppStorage("notifyOwnActivity") private var notifyOwnActivity = false

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
                Toggle("Notify about new GitHub notifications", isOn: $notifyInbox)
                Toggle("Include activity on my own pull requests and issues", isOn: $notifyOwnActivity)
                    .disabled(!notifyInbox)
                    .padding(.leading, 20)
                Toggle("Notify when a workflow run starts", isOn: $notifyStartedRuns)
                Toggle("Notify when a workflow run finishes", isOn: $notifyFinishedRuns)
                Toggle("Notify when a workflow starts failing", isOn: $notifyFailures)
            }
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

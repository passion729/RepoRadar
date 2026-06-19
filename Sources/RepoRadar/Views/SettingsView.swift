import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var loc: Localizer
    @Environment(\.fontTheme) private var theme
    @Environment(\.openURL) private var openURL
    @State private var tokenInput = ""
    @State private var saved = false

    private var isLoggedIn: Bool { !state.token.isEmpty }

    var body: some View {
        Form {
            Section(loc(.languageSectionTitle)) {
                Picker(loc(.interfaceLanguage), selection: $loc.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
            }

            Section(loc(.fontSectionTitle)) {
                Picker(loc(.uiFontFamilyLabel), selection: $state.uiFontFamily) {
                    Text(loc(.systemFont)).tag("")
                    Divider()
                    ForEach(FontCatalog.uiFamilies, id: \.self) { family in
                        Text(family).font(.custom(family, size: 13)).tag(family)
                    }
                }
                Stepper(
                    value: $state.uiFontSize,
                    in: FontSettings.minSize...FontSettings.maxSize
                ) {
                    Text(loc(.uiFontSizeLabel(state.uiFontSize)))
                }

                Picker(loc(.monoFontFamilyLabel), selection: $state.monoFontFamily) {
                    Text(loc(.systemMonoFont)).tag("")
                    Divider()
                    ForEach(FontCatalog.monoFamilies, id: \.self) { family in
                        Text(family).font(.custom(family, size: 13)).tag(family)
                    }
                }
                Stepper(
                    value: $state.monoFontSize,
                    in: FontSettings.minSize...FontSettings.maxSize
                ) {
                    Text(loc(.monoFontSizeLabel(state.monoFontSize)))
                        .font(.custom(state.monoFontFamily.isEmpty ? "Menlo" : state.monoFontFamily,
                                      size: CGFloat(state.monoFontSize)))
                }
            }

            Section(loc(.menuFontSectionTitle)) {
                Picker(loc(.menuFontFamilyLabel), selection: $state.menuFontFamily) {
                    Text(loc(.systemFont)).tag("")
                    Divider()
                    ForEach(FontCatalog.uiFamilies, id: \.self) { family in
                        Text(family).font(.custom(family, size: 13)).tag(family)
                    }
                }
                Stepper(
                    value: $state.menuFontSize,
                    in: FontSettings.minSize...FontSettings.maxSize
                ) {
                    Text(loc(.menuFontSizeLabel(state.menuFontSize)))
                }
            }

            Section(loc(.loginSectionTitle)) {
                if isLoggedIn {
                    HStack {
                        Label(loc(.loggedIn), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Button(loc(.signOut), role: .destructive) {
                            state.signOut()
                            tokenInput = ""
                            saved = false
                        }
                    }
                } else if let prompt = state.deviceCode {
                    deviceCodeView(prompt)
                } else {
                    Button {
                        Task { await state.startDeviceFlow() }
                    } label: {
                        Label(loc(.signInWithGitHub), systemImage: "person.badge.key")
                    }
                    Text(loc(.deviceFlowHint))
                        .font(theme.ui(.caption))
                        .foregroundStyle(.secondary)
                }
            }

            Section(loc(.patSectionTitle)) {
                SecureField("Personal Access Token", text: $tokenInput)
                Text(loc(.patHint))
                    .font(theme.ui(.caption))
                    .foregroundStyle(.secondary)
                HStack {
                    Button(loc(.save)) {
                        state.saveToken(tokenInput)
                        saved = true
                        Task { await state.refresh() }
                    }
                    if saved {
                        Label(loc(.saved), systemImage: "checkmark.circle.fill")
                            .font(theme.ui(.caption))
                            .foregroundStyle(.green)
                    }
                    Spacer()
                    Link(loc(.createToken), destination: URL(string: "https://github.com/settings/tokens")!)
                        .font(theme.ui(.caption))
                }
            }

            Section(loc(.refresh)) {
                Stepper(
                    value: $state.refreshIntervalMinutes,
                    in: AppState.minRefreshMinutes...120
                ) {
                    Text(loc(.refreshIntervalLabel(state.refreshIntervalMinutes)))
                }
                Text(loc(.refreshSectionHint))
                    .font(theme.ui(.caption))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 560)
        .onChange(of: tokenInput) { _, _ in saved = false }
        .onAppear { tokenInput = state.token }
    }

    @ViewBuilder
    private func deviceCodeView(_ prompt: AppState.DeviceCodePrompt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc(.enterDeviceCode))
                .font(theme.ui(.caption))
                .foregroundStyle(.secondary)
            Text(prompt.userCode)
                .font(theme.mono(.title2, weight: .bold))
                .textSelection(.enabled)
            HStack {
                Button(loc(.copyAndOpenGitHub)) { copyAndOpen(prompt) }
                    .buttonStyle(.borderedProminent)
                ProgressView().controlSize(.small)
                Text(loc(.waitingForAuth))
                    .font(theme.ui(.caption))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(loc(.cancel), role: .cancel) { state.cancelDeviceFlow() }
            }
        }
        .onAppear { copyAndOpen(prompt) }
    }

    private func copyAndOpen(_ prompt: AppState.DeviceCodePrompt) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt.userCode, forType: .string)
        if let url = URL(string: prompt.verificationURI) {
            openURL(url)
        }
    }
}

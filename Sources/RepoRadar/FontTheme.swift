import SwiftUI
import AppKit

/// Installed font families, computed once on first use.
enum FontCatalog {
    static let families: [String] = NSFontManager.shared.availableFontFamilies
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

    /// Families whose faces are fixed-pitch.
    static let monoFamilies: [String] = families.filter { family in
        guard let postScriptName = NSFontManager.shared.availableMembers(ofFontFamily: family)?.first?.first as? String,
              let font = NSFont(name: postScriptName, size: 12) else { return false }
        return font.isFixedPitch
    }
}

/// Text styles as point offsets from the body size, matching the macOS system proportions (body 13).
enum FontRole {
    case caption, callout, body, headline, title3, title2

    var offset: CGFloat {
        switch self {
        case .caption: -3
        case .callout: -1
        case .body, .headline: 0
        case .title3: 2
        case .title2: 4
        }
    }
}

/// Fonts resolved from the user's Appearance settings. An empty family means the system font.
struct FontTheme: Equatable {
    var family = ""
    var monoFamily = ""
    var size: CGFloat = 13
    /// Multiplier for zoomable canvases (the workflow graph); 1 everywhere else.
    var zoom: CGFloat = 1

    func font(_ role: FontRole = .body, mono: Bool = false, weight: Font.Weight? = nil) -> Font {
        let points = max(8, size + role.offset) * zoom
        let chosen = mono ? monoFamily : family
        let base = chosen.isEmpty
            ? Font.system(size: points, design: mono ? .monospaced : .default)
            : Font.custom(chosen, fixedSize: points)
        return base.weight(weight ?? (role == .headline ? .semibold : .regular))
    }
}

private struct FontThemeKey: EnvironmentKey {
    static let defaultValue = FontTheme()
}

extension EnvironmentValues {
    var fontTheme: FontTheme {
        get { self[FontThemeKey.self] }
        set { self[FontThemeKey.self] = newValue }
    }
}

extension View {
    /// Themed replacement for `.themeFont(.callout)` etc.
    func themeFont(_ role: FontRole, mono: Bool = false, weight: Font.Weight? = nil) -> some View {
        modifier(ThemeFontModifier(role: role, mono: mono, weight: weight))
    }

    /// Reads the Appearance settings and makes the themed body font the default for everything inside.
    func appliesFontTheme() -> some View {
        modifier(FontThemeRoot())
    }
}

private struct ThemeFontModifier: ViewModifier {
    @Environment(\.fontTheme) private var theme
    let role: FontRole
    let mono: Bool
    let weight: Font.Weight?

    func body(content: Content) -> some View {
        content.font(theme.font(role, mono: mono, weight: weight))
    }
}

private struct FontThemeRoot: ViewModifier {
    @AppStorage("fontFamily") private var family = ""
    @AppStorage("monoFontFamily") private var monoFamily = ""
    @AppStorage("fontSize") private var size = 13.0

    func body(content: Content) -> some View {
        let theme = FontTheme(family: family, monoFamily: monoFamily, size: size)
        content
            .environment(\.fontTheme, theme)
            .font(theme.font())
    }
}

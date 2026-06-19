import SwiftUI
import AppKit

/// Installed-font enumeration. Lists are computed once on first use.
enum FontCatalog {
    /// Sentinel meaning "use the system font" (an empty stored family name).
    static let systemSentinel = ""

    /// All installed font families, alphabetically.
    static let uiFamilies: [String] =
        NSFontManager.shared.availableFontFamilies.sorted(by: localizedLess)

    /// Installed families whose faces are fixed-pitch (monospaced).
    static let monoFamilies: [String] = {
        NSFontManager.shared.availableFontFamilies.filter { family in
            guard
                let members = NSFontManager.shared.availableMembers(ofFontFamily: family),
                let postScriptName = members.first?.first as? String,
                let font = NSFont(name: postScriptName, size: 12)
            else { return false }
            return font.isFixedPitch
        }
        .sorted(by: localizedLess)
    }()

    static func isInstalledUIFamily(_ name: String) -> Bool {
        uiFamilies.contains(name)
    }
    static func isInstalledMonoFamily(_ name: String) -> Bool {
        monoFamilies.contains(name)
    }

    private static func localizedLess(_ a: String, _ b: String) -> Bool {
        a.localizedCaseInsensitiveCompare(b) == .orderedAscending
    }
}

/// Text roles, each a fixed point offset from the chosen body size. Mirrors the
/// rough proportions of the macOS system text styles.
enum FontRole {
    case largeTitle, title, title2, headline, body, subheadline, caption, caption2

    var sizeOffset: CGFloat {
        switch self {
        case .largeTitle: return 12
        case .title: return 8
        case .title2: return 4
        case .headline: return 1
        case .body: return 0
        case .subheadline: return -2
        case .caption: return -3
        case .caption2: return -4
        }
    }

    var defaultWeight: Font.Weight {
        switch self {
        case .headline: return .semibold
        default: return .regular
        }
    }
}

/// Resolves concrete fonts from the user's font settings. UI text uses the
/// chosen UI family (or the system font); monospaced text uses the chosen mono
/// family (or the system monospaced font). Sizes are precise point values.
struct FontTheme {
    /// Empty string = system font.
    var uiFamily: String
    var uiBodySize: CGFloat
    /// Empty string = system monospaced font.
    var monoFamily: String
    var monoBodySize: CGFloat

    func ui(_ role: FontRole, weight: Font.Weight? = nil) -> Font {
        let size = max(1, uiBodySize + role.sizeOffset)
        let base = uiFamily.isEmpty
            ? Font.system(size: size)
            : Font.custom(uiFamily, fixedSize: size)
        return base.weight(weight ?? role.defaultWeight)
    }

    func mono(_ role: FontRole, weight: Font.Weight? = nil) -> Font {
        let size = max(1, monoBodySize + role.sizeOffset)
        let base = monoFamily.isEmpty
            ? Font.system(size: size, design: .monospaced)
            : Font.custom(monoFamily, fixedSize: size)
        return base.weight(weight ?? role.defaultWeight)
    }
}

// MARK: - Environment

private struct FontThemeKey: EnvironmentKey {
    static let defaultValue = FontTheme(uiFamily: "", uiBodySize: 14, monoFamily: "", monoBodySize: 14)
}

extension EnvironmentValues {
    var fontTheme: FontTheme {
        get { self[FontThemeKey.self] }
        set { self[FontThemeKey.self] = newValue }
    }
}

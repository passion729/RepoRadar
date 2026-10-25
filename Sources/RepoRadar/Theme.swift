import AppKit
import SwiftUI

// Design tokens (redesign spec §2). Views take colors, type and radii from here, never literal values.

extension Color {
    /// A color that follows the light / dark appearance.
    static func dynamic(light: Color, dark: Color) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        })
    }

    /// sRGB from 0–255 components, as the spec writes them.
    init(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) {
        self.init(.sRGB, red: red / 255, green: green / 255, blue: blue / 255, opacity: alpha)
    }

    /// 0xRRGGBB.
    init(hex value: UInt32, alpha: Double = 1) {
        self.init(Double((value >> 16) & 0xFF), Double((value >> 8) & 0xFF), Double(value & 0xFF), alpha)
    }
}

enum Theme {
    enum Surface {
        static let window = Color.dynamic(light: Color(243, 244, 247, 0.82), dark: Color(30, 30, 34, 0.86))
        static let sidebar = Color.dynamic(light: Color(233, 235, 241, 0.80), dark: Color(44, 44, 50, 0.72))
        static let toolbar = Color.dynamic(light: Color(249, 249, 251, 0.74), dark: Color(38, 38, 43, 0.78))
        static let pane = Color.dynamic(light: Color(255, 255, 255, 0.70), dark: Color(255, 255, 255, 0.084))
        /// Buttons, fields, graph nodes, comment boxes.
        static let raised = Color.dynamic(light: Color(hex: 0xFFFFFF), dark: Color(hex: 0x3A3A41))
        /// Logs and code: dark in both appearances.
        static let log = Color.dynamic(light: Color(hex: 0x1C1D21), dark: Color(hex: 0x141417))
    }

    /// Text colors (`Text` would shadow SwiftUI's view inside `Theme`).
    enum Ink {
        static let primary = Color.dynamic(light: Color(hex: 0x1D1D1F), dark: Color(hex: 0xF2F2F5))
        static let body = Color.dynamic(light: Color(hex: 0x2A2A30), dark: Color(hex: 0xE4E4EA))
        static let secondary = Color.dynamic(light: Color(hex: 0x5B5B63), dark: Color(hex: 0xA9A9B3))
        static let tertiary = Color.dynamic(light: Color(hex: 0x6B6B73), dark: Color(hex: 0x9B9BA5))
        static let link = Color.dynamic(light: Color(hex: 0x0058C4), dark: Color(hex: 0x6FB2FF))
    }

    static let separator = Color.dynamic(light: Color(0, 0, 0, 0.08), dark: Color(255, 255, 255, 0.096))
    static let accent = Color(hex: 0x0060CC)
    static let accentHover = Color(hex: 0x0054B4)
    static let accentPressed = Color(hex: 0x004A9E)
    static let merge = Color(hex: 0x1A7F37)

    enum Fill {
        static let subtle = Color.dynamic(light: Color(0, 0, 0, 0.05), dark: Color(255, 255, 255, 0.06))
        static let hover = Color.dynamic(light: Color(0, 0, 0, 0.045), dark: Color(255, 255, 255, 0.054))
    }

    enum Selection {
        /// Sidebar selection: gray, as in macOS 27.
        static let nav = Color.dynamic(light: Color(0, 0, 0, 0.085), dark: Color(255, 255, 255, 0.102))
        /// List rows; draw a 20% stroke of `rowStroke` around it.
        static let row = Color.dynamic(light: Color(0, 96, 204, 0.06), dark: Color(64, 156, 255, 0.093))
        static let rowStroke = Color.dynamic(light: Color(0, 96, 204, 0.20), dark: Color(64, 156, 255, 0.20))
    }

    /// Fixed brand colors of the sidebar sections.
    enum Nav {
        static let now = Color(hex: 0x5856D6)
        static let inbox = Color(hex: 0x0071E3)
        static let pulls = Color(hex: 0x8250DF)
        static let actions = Color(hex: 0xD1242F)
    }

    enum Radius {
        static let row: CGFloat = 13
        static let nav: CGFloat = 10
        static let node: CGFloat = 12
        static let log: CGFloat = 14
        static let repoSquare: CGFloat = 9
        static let comment: CGFloat = 8
        static let kbd: CGFloat = 5
    }

    /// Spacing runs in steps of 2.
    enum Space {
        static let iconText: CGFloat = 6
        static let rowPadding: CGFloat = 12
        static let pane: CGFloat = 20
        static let section: CGFloat = 24
    }
}

// MARK: - Tones

/// The semantic color families shared by chips, badges, icon blocks and status icons.
/// Icons and swatches look the same in both appearances; text darkens or lightens with it.
enum Tone: CaseIterable {
    case blue, red, green, amber, purple, neutral

    /// Icon or swatch color.
    var solid: Color {
        switch self {
        case .blue: Theme.accent
        case .red: Color(hex: 0xE5484D)
        case .green: Color(hex: 0x2DA44E)
        case .amber: Color(hex: 0xE08A00)
        case .purple: Color(hex: 0x8250DF)
        case .neutral: Color.dynamic(light: Color(hex: 0xC7C7CC), dark: Color(hex: 0x5D5D65))
        }
    }

    /// Text on a tinted background, or colored text on its own.
    var text: Color {
        switch self {
        case .blue: Theme.Ink.link
        case .red: Color.dynamic(light: Color(hex: 0xB3141F), dark: Color(hex: 0xFF8F94))
        case .green: Color.dynamic(light: Color(hex: 0x146C2E), dark: Color(hex: 0x62D590))
        case .amber: Color.dynamic(light: Color(hex: 0x8A4B00), dark: Color(hex: 0xF5B35C))
        case .purple: Color.dynamic(light: Color(hex: 0x6236C4), dark: Color(hex: 0xBBA0FF))
        case .neutral: Theme.Ink.secondary
        }
    }

    /// Background of chips and icon blocks.
    var tint: Color {
        switch self {
        case .blue: Color.dynamic(light: Color(0, 96, 204, 0.10), dark: Color(64, 156, 255, 0.17))
        case .red: Color.dynamic(light: Color(209, 36, 47, 0.10), dark: Color(255, 92, 98, 0.17))
        case .green: Color.dynamic(light: Color(26, 127, 55, 0.11), dark: Color(70, 200, 110, 0.18))
        case .amber: Color.dynamic(light: Color(214, 130, 0, 0.14), dark: Color(255, 170, 60, 0.21))
        case .purple: Color.dynamic(light: Color(130, 80, 223, 0.11), dark: Color(170, 130, 255, 0.20))
        case .neutral: Theme.Fill.subtle
        }
    }
}

// MARK: - Type

/// The type ramp (spec §2), as size / weight / line height. Every style uses tabular digits.
enum TextStyle: CaseIterable {
    case bigNumber, detailTitle, paneTitle, toolbarTitle, queueTitle, rowTitle, body, button, meta, label, kbd, log

    var size: CGFloat {
        switch self {
        case .bigNumber: 30
        case .detailTitle: 21
        case .paneTitle: 16
        case .toolbarTitle: 15
        case .queueTitle: 13.5
        case .rowTitle, .body: 13
        case .button: 12.5
        case .meta: 12
        case .label, .log: 11
        case .kbd: 10.5
        }
    }

    var weight: Font.Weight {
        switch self {
        case .detailTitle, .paneTitle, .toolbarTitle: .bold
        case .bigNumber, .queueTitle, .rowTitle, .label, .kbd: .semibold
        case .button: .medium
        case .body, .meta, .log: .regular
        }
    }

    /// Line height as a multiple of the size; nil keeps the font's own.
    var lineHeight: CGFloat? {
        switch self {
        case .body: 1.55
        case .log: 1.65
        default: nil
        }
    }

    /// Letter spacing in em.
    var tracking: CGFloat {
        switch self {
        case .bigNumber: -0.02
        case .detailTitle, .paneTitle: -0.01
        default: 0
        }
    }

    var isMono: Bool { self == .log }
}

extension View {
    /// Applies a type-ramp style. It follows the Appearance settings: their family, and their size relative to 13 pt.
    func textStyle(_ style: TextStyle) -> some View {
        modifier(TextStyleModifier(style: style))
    }
}

private struct TextStyleModifier: ViewModifier {
    @Environment(\.fontTheme) private var theme
    let style: TextStyle

    func body(content: Content) -> some View {
        let points = style.size * theme.size / 13 * theme.zoom
        let family = style.isMono ? theme.monoFamily : theme.family
        let font = family.isEmpty
            ? Font.system(size: points, weight: style.weight, design: style.isMono ? .monospaced : .default)
            : Font.custom(family, fixedSize: points).weight(style.weight)
        content
            .font(font.monospacedDigit())
            .tracking(style.tracking * points)
            // SwiftUI's default line height is about 1.2× the size; add the rest between lines.
            .lineSpacing(style.lineHeight.map { max(0, ($0 - 1.2) * points) } ?? 0)
    }
}

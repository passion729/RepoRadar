import SwiftUI

// Buttons (spec §4): 30 pt capsules in four kinds, plus round icon buttons and the toolbar search field.

struct CapsuleButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost, merge }
    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        CapsuleButton(kind: kind, configuration: configuration)
    }
}

extension ButtonStyle where Self == CapsuleButtonStyle {
    /// Accent fill. At most one per row.
    static var primary: CapsuleButtonStyle { .init(kind: .primary) }
    /// Raised surface with a hairline. Destructive actions use this plus a confirmation, never red.
    static var secondary: CapsuleButtonStyle { .init(kind: .secondary) }
    /// No fill until hovered; for secondary actions at the end of a row.
    static var ghost: CapsuleButtonStyle { .init(kind: .ghost) }
    /// Green, only for merging.
    static var merge: CapsuleButtonStyle { .init(kind: .merge) }
}

private struct CapsuleButton: View {
    let kind: CapsuleButtonStyle.Kind
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.controlSize) private var controlSize
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .labelStyle(ButtonLabelStyle())
            .textStyle(.button)
            .lineLimit(1)
            .padding(.horizontal, 13)
            .frame(height: controlSize == .small || controlSize == .mini ? 26 : 30)
            .foregroundStyle(kind == .primary || kind == .merge ? Color.white : Theme.Ink.primary)
            .background(fill, in: .capsule)
            .overlay {
                if kind == .secondary {
                    Capsule().strokeBorder(Theme.Ink.primary.opacity(isHovered && isEnabled ? 0.18 : 0.10), lineWidth: 1)
                }
            }
            .overlay {
                if isFocused {
                    Capsule().inset(by: -1.5).stroke(Theme.accent.opacity(0.35), lineWidth: 3)
                }
            }
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(.capsule)
            .onHover { isHovered = $0 }
    }

    private var fill: Color {
        let pressed = configuration.isPressed
        let hovered = isHovered && isEnabled
        switch kind {
        case .primary: return pressed ? Theme.accentPressed : hovered ? Theme.accentHover : Theme.accent
        case .merge: return pressed ? Color(hex: 0x14612A) : hovered ? Color(hex: 0x176F30) : Theme.merge
        case .secondary: return pressed ? Theme.Selection.nav : Theme.Surface.raised.opacity(0.9)
        case .ghost: return pressed ? Theme.Selection.nav : hovered ? Theme.Fill.subtle : .clear
        }
    }
}

/// 14 pt icon, 6 pt from the title.
private struct ButtonLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Theme.Space.iconText) {
            configuration.icon.font(.system(size: 14))
            configuration.title
        }
    }
}

// MARK: - Icon buttons

/// Round, icon-only button: 32 pt alone, 28 pt inside an `IconButtonGroup`.
/// Give the button a title (`Button("Refresh", systemImage: …)`): it becomes the accessibility label and tooltip.
struct IconButtonStyle: ButtonStyle {
    var diameter: CGFloat = 32

    func makeBody(configuration: Configuration) -> some View {
        IconButton(diameter: diameter, configuration: configuration)
    }
}

extension ButtonStyle where Self == IconButtonStyle {
    static var icon: IconButtonStyle { .init() }
}

private struct IconButton: View {
    let diameter: CGFloat
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Theme.Ink.primary)
            .frame(width: diameter, height: diameter)
            .background(configuration.isPressed ? Theme.Selection.nav : isHovered && isEnabled ? Theme.Fill.hover : .clear, in: .circle)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(.circle)
            .onHover { isHovered = $0 }
    }
}

/// Related icon buttons on one `fill.subtle` capsule.
struct IconButtonGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) { content }
            .buttonStyle(IconButtonStyle(diameter: 28))
            .padding(2)
            .background(Theme.Fill.subtle, in: .capsule)
    }
}

// MARK: - Search field

/// The toolbar search: 32 pt capsule on `fill.subtle`, with a shortcut hint on the right.
struct SearchField: View {
    let prompt: String
    @Binding var text: String
    var shortcut: String? = "⌘K"
    /// Reports when the field gains or loses the cursor.
    var onFocusChange: ((Bool) -> Void)?
    /// Arrow keys and return while typing (for a results list); return `.ignored` to let the field have them.
    var onKey: ((KeyPress) -> KeyPress.Result)?
    @FocusState private var isFocused: Bool

    static let toolbarPrompt = "Search or jump to…"

    /// ⌘K: puts the cursor in the key window's toolbar search field.
    /// Found through AppKit: a `FocusState` set from a menu command doesn't reach a field inside the toolbar.
    @MainActor static func focusInKeyWindow() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let field = textField(placeholder: toolbarPrompt, in: window.contentView?.superview) else { return }
        window.makeFirstResponder(field)
    }

    @MainActor private static func textField(placeholder: String, in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField, field.isEditable, field.placeholderString == placeholder { return field }
        for subview in view.subviews {
            if let field = textField(placeholder: placeholder, in: subview) { return field }
        }
        return nil
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.Ink.tertiary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text, prompt: Text(prompt).foregroundStyle(Theme.Ink.tertiary))
                .textFieldStyle(.plain)
                .textStyle(.meta)
                .focused($isFocused)
                .onChange(of: isFocused) { _, focused in onFocusChange?(focused) }
                .onKeyPress(keys: [.upArrow, .downArrow, .return], phases: .down) { press in onKey?(press) ?? .ignored }
                .onExitCommand { text = "" }
            if !text.isEmpty {
                Button("Clear Search", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.Ink.tertiary)
            } else if let shortcut {
                Kbd(shortcut)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 7)
        .frame(height: 32)
        .background(Theme.Fill.subtle, in: .capsule)
    }
}

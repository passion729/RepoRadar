import Testing
@testable import RepoRadar

/// Spec §8: body text at least 4.5:1. Token values from spec §2, composited over the window background the
/// way the app draws them (light window ≈ #F3F4F7 on white, dark ≈ #1E1E22).
@Test func textTokensMeetContrast() {
    let lightWindow: UInt32 = 0xF3F4F7, darkWindow: UInt32 = 0x1E1E22
    let light: [String: UInt32] = ["primary": 0x1D1D1F, "body": 0x2A2A30, "secondary": 0x5B5B63, "tertiary": 0x6B6B73, "link": 0x0058C4]
    let dark: [String: UInt32] = ["primary": 0xF2F2F5, "body": 0xE4E4EA, "secondary": 0xA9A9B3, "tertiary": 0x9B9BA5, "link": 0x6FB2FF]
    for (name, color) in light { #expect(LabelColors.contrast(color, lightWindow) >= 4.5, "light \(name)") }
    for (name, color) in dark { #expect(LabelColors.contrast(color, darkWindow) >= 4.5, "dark \(name)") }
}

/// Chip text on its own tint (tint alpha from spec §2 over the window).
@Test func statusTextOnTintsMeetsContrast() {
    let cases: [(text: UInt32, tint: UInt32, alpha: Double, window: UInt32)] = [
        (0xB3141F, 0xD1242F, 0.10, 0xF3F4F7), (0xFF8F94, 0xFF5C62, 0.17, 0x1E1E22),  // red
        (0x146C2E, 0x1A7F37, 0.11, 0xF3F4F7), (0x62D590, 0x46C86E, 0.18, 0x1E1E22),  // green
        (0x8A4B00, 0xD68200, 0.14, 0xF3F4F7), (0xF5B35C, 0xFFAA3C, 0.21, 0x1E1E22),  // amber
        (0x6236C4, 0x8250DF, 0.11, 0xF3F4F7), (0xBBA0FF, 0xAA82FF, 0.20, 0x1E1E22),  // purple
        (0x0058C4, 0x0060CC, 0.10, 0xF3F4F7), (0x6FB2FF, 0x409CFF, 0.17, 0x1E1E22),  // blue
    ]
    for item in cases {
        let background = LabelColors.mix(item.window, item.tint, item.alpha)
        #expect(LabelColors.contrast(item.text, background) >= 4.5, "text \(String(item.text, radix: 16)) on tint")
    }
}

@Test func permissionHintsNameTheMissingScope() {
    #expect(AppState.missingScope(for: .write, in: ["repo", "notifications"]) == nil)
    #expect(AppState.missingScope(for: .write, in: ["notifications"])?.contains("repo scope") == true)
    #expect(AppState.missingScope(for: .inbox, in: ["repo"]) == nil)
    #expect(AppState.missingScope(for: .inbox, in: ["read:org"])?.contains("notifications scope") == true)
    // Fine-grained tokens report no scopes: nothing is blocked up front.
    #expect(AppState.missingScope(for: .write, in: []) == nil && AppState.missingScope(for: .write, in: nil) == nil)
}

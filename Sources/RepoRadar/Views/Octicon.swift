import SwiftUI
import AppKit

/// GitHub octicon path data (16×16 viewBox), copied verbatim from primer/octicons.
enum OcticonPath {
    static let gitPullRequest = "M1.5 3.25a2.25 2.25 0 1 1 3 2.122v5.256a2.251 2.251 0 1 1-1.5 0V5.372A2.25 2.25 0 0 1 1.5 3.25Zm5.677-.177L9.573.677A.25.25 0 0 1 10 .854V2.5h1A2.5 2.5 0 0 1 13.5 5v5.628a2.251 2.251 0 1 1-1.5 0V5a1 1 0 0 0-1-1h-1v1.646a.25.25 0 0 1-.427.177L7.177 3.427a.25.25 0 0 1 0-.354ZM3.75 2.5a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Zm0 9.5a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Zm8.25.75a.75.75 0 1 0 1.5 0 .75.75 0 0 0-1.5 0Z"

    static let gitMerge = "M5.45 5.154A4.25 4.25 0 0 0 9.25 7.5h1.378a2.251 2.251 0 1 1 0 1.5H9.25A5.734 5.734 0 0 1 5 7.123v3.505a2.25 2.25 0 1 1-1.5 0V5.372a2.25 2.25 0 1 1 1.95-.218ZM4.25 13.5a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5Zm8.5-4.5a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5ZM5 3.25a.75.75 0 1 0 0 .005V3.25Z"

    static let gitPullRequestClosed = "M3.25 1A2.25 2.25 0 0 1 4 5.372v5.256a2.251 2.251 0 1 1-1.5 0V5.372A2.251 2.251 0 0 1 3.25 1Zm9.5 5.5a.75.75 0 0 1 .75.75v3.378a2.251 2.251 0 1 1-1.5 0V7.25a.75.75 0 0 1 .75-.75Zm-2.03-5.273a.75.75 0 0 1 1.06 0l.97.97.97-.97a.748.748 0 0 1 1.265.332.75.75 0 0 1-.205.729l-.97.97.97.97a.751.751 0 0 1-.018 1.042.751.751 0 0 1-1.042.018l-.97-.97-.97.97a.749.749 0 0 1-1.275-.326.749.749 0 0 1 .215-.734l.97-.97-.97-.97a.75.75 0 0 1 0-1.06ZM2.5 3.25a.75.75 0 1 0 1.5 0 .75.75 0 0 0-1.5 0ZM3.25 12a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Zm9.5 0a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Z"

    static let markGithub = "M6.766 11.328c-2.063-.25-3.516-1.734-3.516-3.656 0-.781.281-1.625.75-2.188-.203-.515-.172-1.609.063-2.062.625-.078 1.468.25 1.968.703.594-.187 1.219-.281 1.985-.281.765 0 1.39.094 1.953.265.484-.437 1.344-.765 1.969-.687.218.422.25 1.515.046 2.047.5.593.766 1.39.766 2.203 0 1.922-1.453 3.375-3.547 3.64.531.344.89 1.094.89 1.954v1.625c0 .468.391.734.86.547C13.781 14.359 16 11.53 16 8.03 16 3.61 12.406 0 7.984 0 3.563 0 0 3.61 0 8.031a7.88 7.88 0 0 0 5.172 7.422c.422.156.828-.125.828-.547v-1.25c-.219.094-.5.156-.75.156-1.031 0-1.64-.562-2.078-1.609-.172-.422-.36-.672-.719-.719-.187-.015-.25-.093-.25-.187 0-.188.313-.328.625-.328.453 0 .844.281 1.25.86.313.452.64.655 1.031.655s.641-.14 1-.5c.266-.265.47-.5.657-.656"
}

/// Renders a 16×16 octicon SVG path as a tintable, scalable SwiftUI shape.
/// Fill it with `.foregroundStyle(...)` like any Shape.
struct OcticonShape: Shape {
    let data: String

    func path(in rect: CGRect) -> Path {
        SVGPath.build(data, viewBox: 16, in: rect)
    }
}

extension OcticonPath {
    /// A template `NSImage` for status-bar / menu use. `MenuBarExtra` can't
    /// reliably render an arbitrary SwiftUI shape as its label, so we rasterize
    /// the path; `isTemplate = true` lets macOS tint it for light/dark/active.
    static func templateImage(_ data: String, size: CGFloat = 16) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.addPath(SVGPath.build(data, viewBox: 16, in: rect).cgPath)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// Minimal SVG path-data parser → `Path`. Supports M/L/H/V/A/Z (+ lowercase),
/// which covers the octicon set. Elliptical arcs are converted with the W3C
/// endpoint→center algorithm and sampled as a polyline.
private enum SVGPath {
    private enum Token { case cmd(Character); case num(CGFloat) }

    static func build(_ d: String, viewBox: CGFloat, in rect: CGRect) -> Path {
        let tokens = tokenize(d)
        let scale = min(rect.width, rect.height) / viewBox
        func map(_ p: CGPoint) -> CGPoint {
            CGPoint(x: rect.minX + p.x * scale, y: rect.minY + p.y * scale)
        }

        var path = Path()
        var cur = CGPoint.zero
        var start = CGPoint.zero
        var ctrl: CGPoint? = nil   // previous cubic control point (for S/s reflection)
        var idx = 0

        func nextNum() -> CGFloat {
            while idx < tokens.count {
                if case .num(let v) = tokens[idx] { idx += 1; return v }
                idx += 1
            }
            return 0
        }
        func peekIsNum() -> Bool {
            guard idx < tokens.count, case .num = tokens[idx] else { return false }
            return true
        }

        while idx < tokens.count {
            guard case .cmd(let raw) = tokens[idx] else { idx += 1; continue }
            idx += 1
            let relative = raw.isLowercase
            // After a moveto, extra coordinate pairs are implicit linetos.
            var command = raw
            repeat {
                switch Character(command.uppercased()) {
                case "M":
                    var p = CGPoint(x: nextNum(), y: nextNum())
                    if relative { p = CGPoint(x: cur.x + p.x, y: cur.y + p.y) }
                    cur = p; start = p; ctrl = nil
                    path.move(to: map(p))
                    command = relative ? "l" : "L"   // subsequent pairs = lineto
                case "L":
                    var p = CGPoint(x: nextNum(), y: nextNum())
                    if relative { p = CGPoint(x: cur.x + p.x, y: cur.y + p.y) }
                    cur = p; ctrl = nil; path.addLine(to: map(p))
                case "H":
                    var x = nextNum(); if relative { x += cur.x }
                    cur.x = x; ctrl = nil; path.addLine(to: map(cur))
                case "V":
                    var y = nextNum(); if relative { y += cur.y }
                    cur.y = y; ctrl = nil; path.addLine(to: map(cur))
                case "C":
                    var c1 = CGPoint(x: nextNum(), y: nextNum())
                    var c2 = CGPoint(x: nextNum(), y: nextNum())
                    var p = CGPoint(x: nextNum(), y: nextNum())
                    if relative {
                        c1 = CGPoint(x: cur.x + c1.x, y: cur.y + c1.y)
                        c2 = CGPoint(x: cur.x + c2.x, y: cur.y + c2.y)
                        p = CGPoint(x: cur.x + p.x, y: cur.y + p.y)
                    }
                    path.addCurve(to: map(p), control1: map(c1), control2: map(c2))
                    ctrl = c2; cur = p
                case "S":
                    var c2 = CGPoint(x: nextNum(), y: nextNum())
                    var p = CGPoint(x: nextNum(), y: nextNum())
                    if relative {
                        c2 = CGPoint(x: cur.x + c2.x, y: cur.y + c2.y)
                        p = CGPoint(x: cur.x + p.x, y: cur.y + p.y)
                    }
                    // First control is the reflection of the previous one.
                    let c1 = ctrl.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                    path.addCurve(to: map(p), control1: map(c1), control2: map(c2))
                    ctrl = c2; cur = p
                case "A":
                    let rx = nextNum(), ry = nextNum(), rot = nextNum()
                    let large = nextNum() != 0, sweep = nextNum() != 0
                    var end = CGPoint(x: nextNum(), y: nextNum())
                    if relative { end = CGPoint(x: cur.x + end.x, y: cur.y + end.y) }
                    appendArc(&path, from: cur, to: end, rx: rx, ry: ry,
                              rotationDeg: rot, largeArc: large, sweep: sweep, map: map)
                    cur = end; ctrl = nil
                case "Z":
                    path.closeSubpath(); cur = start; ctrl = nil
                default:
                    return path   // unsupported command — stop safely
                }
            } while peekIsNum() && Character(command.uppercased()) != "Z"
        }
        return path
    }

    private static func appendArc(
        _ path: inout Path, from p0: CGPoint, to p1: CGPoint,
        rx rxIn: CGFloat, ry ryIn: CGFloat, rotationDeg: CGFloat,
        largeArc: Bool, sweep: Bool, map: (CGPoint) -> CGPoint
    ) {
        if p0 == p1 { return }
        var rx = abs(rxIn), ry = abs(ryIn)
        if rx == 0 || ry == 0 { path.addLine(to: map(p1)); return }

        let phi = rotationDeg * .pi / 180
        let cosP = cos(phi), sinP = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1p = cosP * dx + sinP * dy
        let y1p = -sinP * dx + cosP * dy

        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 { let s = sqrt(lambda); rx *= s; ry *= s }

        let sign: CGFloat = (largeArc != sweep) ? 1 : -1
        let num = max(0, rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p)
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        let co = den == 0 ? 0 : sign * sqrt(num / den)
        let cxp = co * (rx * y1p / ry)
        let cyp = co * (-ry * x1p / rx)
        let cx = cosP * cxp - sinP * cyp + (p0.x + p1.x) / 2
        let cy = sinP * cxp + cosP * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
            var a = acos(max(-1, min(1, len == 0 ? 1 : dot / len)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var dTheta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && dTheta > 0 { dTheta -= 2 * .pi }
        if sweep && dTheta < 0 { dTheta += 2 * .pi }

        let segments = max(2, Int(ceil(abs(dTheta) / (.pi / 16))))
        for s in 1...segments {
            let t = theta1 + dTheta * CGFloat(s) / CGFloat(segments)
            let x = cx + rx * cosP * cos(t) - ry * sinP * sin(t)
            let y = cy + rx * sinP * cos(t) + ry * cosP * sin(t)
            path.addLine(to: map(CGPoint(x: x, y: y)))
        }
    }

    private static func tokenize(_ d: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(d)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == " " || c == "," || c == "\n" || c == "\t" || c == "\r" { i += 1; continue }
            if c.isLetter { tokens.append(.cmd(c)); i += 1; continue }

            var s = ""
            if c == "-" || c == "+" { s.append(c); i += 1 }
            var hasDot = false
            while i < chars.count {
                let ch = chars[i]
                if ch.isNumber {
                    s.append(ch); i += 1
                } else if ch == "." {
                    if hasDot { break }
                    hasDot = true; s.append(ch); i += 1
                } else if ch == "e" || ch == "E" {
                    s.append(ch); i += 1
                    if i < chars.count, chars[i] == "-" || chars[i] == "+" { s.append(chars[i]); i += 1 }
                } else {
                    break
                }
            }
            if let v = Double(s) { tokens.append(.num(CGFloat(v))) }
        }
        return tokens
    }
}

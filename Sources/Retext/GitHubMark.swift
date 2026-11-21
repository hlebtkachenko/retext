import SwiftUI

/// The GitHub mark, drawn from Primer Octicons' `mark-github-16` path (MIT License, Copyright (c) GitHub Inc.,
/// https://github.com/primer/octicons), scaled to fit the frame.
struct GitHubMark: Shape {
    static let svg = "M6.766 11.328c-2.063-.25-3.516-1.734-3.516-3.656 0-.781.281-1.625.75-2.188-.203-.515-.172-1.609.063-2.062.625-.078 1.468.25 1.968.703.594-.187 1.219-.281 1.985-.281.765 0 1.39.094 1.953.265.484-.437 1.344-.765 1.969-.687.218.422.25 1.515.046 2.047.5.593.766 1.39.766 2.203 0 1.922-1.453 3.375-3.547 3.64.531.344.89 1.094.89 1.954v1.625c0 .468.391.734.86.547C13.781 14.359 16 11.53 16 8.03 16 3.61 12.406 0 7.984 0 3.563 0 0 3.61 0 8.031a7.88 7.88 0 0 0 5.172 7.422c.422.156.828-.125.828-.547v-1.25c-.219.094-.5.156-.75.156-1.031 0-1.64-.562-2.078-1.609-.172-.422-.36-.672-.719-.719-.187-.015-.25-.093-.25-.187 0-.188.313-.328.625-.328.453 0 .844.281 1.25.86.313.452.64.655 1.031.655s.641-.14 1-.5c.266-.265.47-.5.657-.656"
    /// The mark in its 16 x 16 view box.
    static let unitPath = SVGPath.parse(svg)

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 16
        let transform = CGAffineTransform(translationX: rect.midX - 8 * scale, y: rect.midY - 8 * scale).scaledBy(x: scale, y: scale)
        return Self.unitPath.applying(transform)
    }
}

/// Just enough of SVG path syntax for the mark: M L H V C S Z and circular arcs (no rotation), absolute and relative.
enum SVGPath {
    static func parse(_ d: String) -> Path {
        var tokens = tokenize(d)[...]
        var path = Path()
        var current = CGPoint.zero, start = CGPoint.zero, lastControl: CGPoint?
        var command: Character = "M"
        func number() -> CGFloat {
            guard case .number(let n)? = tokens.popFirst() else { return 0 }
            return n
        }
        func point(_ relative: Bool) -> CGPoint {
            let x = number(), y = number()
            return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }
        while let token = tokens.first {
            if case .command(let c) = token { command = c; tokens.removeFirst() }
            let relative = command.isLowercase
            switch command.uppercased() {
            case "M":
                current = point(relative); start = current
                path.move(to: current)
                command = relative ? "l" : "L"  // further pairs are lines
                lastControl = nil
            case "L":
                current = point(relative); path.addLine(to: current); lastControl = nil
            case "H":
                let x = number(); current.x = relative ? current.x + x : x; path.addLine(to: current); lastControl = nil
            case "V":
                let y = number(); current.y = relative ? current.y + y : y; path.addLine(to: current); lastControl = nil
            case "C":
                let c1 = point(relative), c2 = point(relative), end = point(relative)
                path.addCurve(to: end, control1: c1, control2: c2)
                lastControl = c2; current = end
            case "S":
                let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let c2 = point(relative), end = point(relative)
                path.addCurve(to: end, control1: c1, control2: c2)
                lastControl = c2; current = end
            case "A":
                let r = number(); _ = number(); _ = number()
                let large = number() != 0, sweep = number() != 0
                let end = point(relative)
                addArc(&path, from: current, to: end, radius: r, large: large, sweep: sweep)
                current = end; lastControl = nil
            case "Z":
                path.closeSubpath(); current = start; lastControl = nil
                if case .number? = tokens.first { tokens.removeFirst() }  // malformed: skip
            default:
                tokens.removeFirst()
            }
        }
        return path
    }

    /// A circular SVG arc via its center (SVG implementation notes, F.6.5, with rx = ry and no rotation).
    private static func addArc(_ path: inout Path, from p0: CGPoint, to p1: CGPoint, radius: CGFloat, large: Bool, sweep: Bool) {
        let mid = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
        let dx = (p1.x - p0.x) / 2, dy = (p1.y - p0.y) / 2
        let half = (dx * dx + dy * dy).squareRoot()
        guard half > 0 else { return }
        let r = max(radius, half)
        var h = (r * r - half * half).squareRoot()
        if large == sweep { h = -h }
        // The center lies on the perpendicular bisector, h from the midpoint.
        let center = CGPoint(x: mid.x - h * dy / half, y: mid.y + h * dx / half)
        let a0 = atan2(p0.y - center.y, p0.x - center.x), a1 = atan2(p1.y - center.y, p1.x - center.x)
        // SVG's positive sweep is clockwise on screen (y down), which is increasing angle here.
        path.addArc(center: center, radius: r, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: !sweep)
    }

    private enum Token { case command(Character), number(CGFloat) }

    /// Splits "M6.766 11.328c-2.063-.25" and "0 0 0 5.172" into commands and numbers; a second "." or a "-" starts a
    /// new number.
    private static func tokenize(_ d: String) -> [Token] {
        var tokens: [Token] = [], buffer = ""
        func flush() {
            if let n = Double(buffer) { tokens.append(.number(CGFloat(n))) }
            buffer = ""
        }
        for ch in d {
            if ch.isLetter && ch != "e" {
                flush(); tokens.append(.command(ch))
            } else if ch == "-" {
                flush(); buffer = "-"
            } else if ch == "." {
                if buffer.contains(".") { flush() }
                buffer.append(ch)
            } else if ch.isNumber {
                buffer.append(ch)
            } else {
                flush()
            }
        }
        flush()
        return tokens
    }
}

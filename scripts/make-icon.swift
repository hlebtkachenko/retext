// Renders the Retext app icon and the launch images. Usage: swift scripts/make-icon.swift
// The icon is the Icon Composer document Resources/AppIcon.icon: icon.json (brand-blue fill, one glass group with
// specular highlights and a shadow) plus the white glyph layers this script writes to its Assets folder as SVG.
// macOS renders the Liquid Glass from that document at run time (build.sh compiles it into Assets.car with actool).
// From the compiled glass render this script also writes Resources/AppIcon.icns (16...512 pt at 1x and 2x, the
// fallback for CFBundleIconFile), docs/images/icon-240.png (Product Hunt) and docs/images/social-preview.png (1280x640).
import AppKit
import CoreText

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources")
let document = resources.appendingPathComponent("AppIcon.icon")
let images = root.appendingPathComponent("docs/images")

// Brand colours, also used in docs/index.html. brandBlue is the icon fill (icon.json holds it as sRGB floats).
// brandBlue: the icon body and the name in the social preview. White on it: 13.1:1.
// accentBlue: links and buttons on light backgrounds. On white: 5.73:1, on #f4f5f7: 5.25:1.
// accentBlueDark: links and buttons in dark mode. On #161618: 7.45:1, brandBlue on it: 5.40:1.
let brandBlue = "#0F2E66"
let accentBlue = "#1F5FD6"
let accentBlueDark = "#7AA5FF"
// Neutrals of the social preview: background and tagline (6.18:1 on the background).
let previewBackground = "#F7F7F9"
let previewGray = "#5C5C66"

func color(_ hex: String) -> NSColor {
    let value = Int(hex.dropFirst(), radix: 16)!
    return NSColor(srgbRed: CGFloat(value >> 16 & 0xFF) / 255, green: CGFloat(value >> 8 & 0xFF) / 255,
                   blue: CGFloat(value & 0xFF) / 255, alpha: 1)
}

func run(_ tool: String, _ arguments: [String]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice // actool prints its result plist; errors still reach stderr.
    try! process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { fatalError("\(tool) \(arguments.joined(separator: " ")) failed") }
}

// MARK: Glyph layers

/// The glyphs on the 1024 pt Icon Composer canvas (the canvas is the icon body): a white "R" (SF Pro Bold) and a
/// text cursor (I-beam) of the same height, returned in CoreGraphics coordinates (origin bottom left).
func glyphs() -> (letter: CGPath, cursor: CGPath) {
    let side: CGFloat = 1024
    // The R as a glyph outline, so its ink (not its advance or line height) is what gets centred.
    let font = NSFont.systemFont(ofSize: side * 0.56, weight: .bold) as CTFont
    var glyph = CGGlyph()
    var character = UniChar(("R" as Character).asciiValue!)
    guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1),
          let letter = CTFontCreatePathForGlyph(font, glyph, nil) else { fatalError("No R glyph in the system font") }
    let ink = letter.boundingBoxOfPath
    let capHeight = CTFontGetCapHeight(font)

    // The I-beam: a thin stem with short bars at the cap height and the baseline, much lighter than the R,
    // so it reads as a text cursor and not as a serif capital I.
    let stem = capHeight * 0.075
    let bar = capHeight * 0.065
    let beamWidth = capHeight * 0.36
    let gap = capHeight * 0.12
    let total = ink.width + gap + beamWidth

    // Optical centre: the group's ink box sits on the canvas centre, nudged up 1% because a shape looks low at true centre.
    let originX = side / 2 - total / 2 - ink.minX
    let originY = side / 2 - capHeight / 2 + side * 0.01
    let placedLetter = CGMutablePath()
    placedLetter.addPath(letter, transform: CGAffineTransform(translationX: originX, y: originY))
    // Three non-overlapping rectangles, so the glass layer has no inner seams.
    let beamX = originX + ink.maxX + gap
    let cursor = CGMutablePath()
    cursor.addRect(CGRect(x: beamX + (beamWidth - stem) / 2, y: originY + bar, width: stem, height: capHeight - 2 * bar))
    cursor.addRect(CGRect(x: beamX, y: originY, width: beamWidth, height: bar))
    cursor.addRect(CGRect(x: beamX, y: originY + capHeight - bar, width: beamWidth, height: bar))
    return (placedLetter, cursor)
}

/// A 1024 pt SVG with `path` filled white (Icon Composer applies the glass; the fill colour stays the source's).
func svg(_ path: CGPath) -> String {
    var data = ""
    func point(_ p: CGPoint) -> String { String(format: "%.2f %.2f", p.x, 1024 - p.y) } // SVG y points down.
    path.applyWithBlock { element in
        let points = element.pointee.points
        switch element.pointee.type {
        case .moveToPoint: data += "M\(point(points[0]))"
        case .addLineToPoint: data += "L\(point(points[0]))"
        case .addQuadCurveToPoint: data += "Q\(point(points[0])) \(point(points[1]))"
        case .addCurveToPoint: data += "C\(point(points[0])) \(point(points[1])) \(point(points[2]))"
        case .closeSubpath: data += "Z"
        @unknown default: fatalError("Unknown path element")
        }
    }
    return """
    <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">\
    <path fill="#FFFFFF" d="\(data)"/></svg>

    """
}

let assets = document.appendingPathComponent("Assets")
try! FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
let (letter, cursor) = glyphs()
try! svg(letter).write(to: assets.appendingPathComponent("R.svg"), atomically: true, encoding: .utf8)
try! svg(cursor).write(to: assets.appendingPathComponent("Cursor.svg"), atomically: true, encoding: .utf8)

// MARK: Glass render

// Compile the document the way build.sh does, into a throwaway bundle, and let AppKit render the glass from it.
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("Retext-\(UUID().uuidString)")
let bundle = temporary.appendingPathComponent("Icon.bundle")
let compiled = bundle.appendingPathComponent("Contents/Resources")
try! FileManager.default.createDirectory(at: compiled, withIntermediateDirectories: true)
try! FileManager.default.copyItem(at: root.appendingPathComponent("Info.plist"),
                                  to: bundle.appendingPathComponent("Contents/Info.plist"))
run("/usr/bin/xcrun", ["actool", document.path, "--compile", compiled.path, "--platform", "macosx",
                       "--minimum-deployment-target", "26.0", "--app-icon", "AppIcon",
                       "--output-partial-info-plist", temporary.appendingPathComponent("partial.plist").path])
guard let icon = Bundle(url: bundle)?.image(forResource: "AppIcon") else { fatalError("actool produced no AppIcon") }

/// Draws into a bitmap of exactly `width` x `height` pixels (NSImage.lockFocus would double on Retina).
func render(_ width: Int, _ height: Int, _ draw: (CGRect) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    // The light-mode render: the published images and the icns fallback show the icon as the Finder does by default.
    NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance { draw(CGRect(x: 0, y: 0, width: width, height: height)) }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, _ url: URL) {
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let iconset = temporary.appendingPathComponent("AppIcon.iconset")
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try! FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let name = factor == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        write(render(points * factor, points * factor) { icon.draw(in: $0) }, iconset.appendingPathComponent(name))
    }
}
run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path])

// Product Hunt thumbnail: the full rounded square, edge to edge (the body is 824 of the 1024 pt icon canvas).
write(render(240, 240) { rect in icon.draw(in: rect.insetBy(dx: -rect.width * 100 / 824, dy: -rect.height * 100 / 824)) },
      images.appendingPathComponent("icon-240.png"))

// Social preview (GitHub, Open Graph): icon, name and tagline on a flat background.
write(render(1280, 640) { rect in
    color(previewBackground).setFill()
    rect.fill()
    icon.draw(in: CGRect(x: 96, y: 160, width: 320, height: 320))
    let name = NSAttributedString(string: "Retext", attributes: [
        .font: NSFont.systemFont(ofSize: 112, weight: .bold),
        .foregroundColor: color(brandBlue),
    ])
    name.draw(at: CGPoint(x: 456, y: 324))
    let tagline = NSAttributedString(string: "Fix, translate and rewrite text\nin any Mac app", attributes: [
        .font: NSFont.systemFont(ofSize: 44, weight: .regular),
        .foregroundColor: color(previewGray),
    ])
    tagline.draw(in: CGRect(x: 460, y: 170, width: 780, height: 140))
}, images.appendingPathComponent("social-preview.png"))

print("Wrote \(assets.path)/R.svg, Cursor.svg, \(resources.path)/AppIcon.icns and docs/images/icon-240.png, social-preview.png")

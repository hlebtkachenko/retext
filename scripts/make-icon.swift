// Renders the Retext app icon and the launch images. Usage: swift scripts/make-icon.swift
// Writes Resources/AppIcon.icns (16...512 pt at 1x and 2x, via a temporary iconset and iconutil),
// docs/images/icon-240.png (Product Hunt) and docs/images/social-preview.png (1280x640).
import AppKit
import CoreText

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources")
let images = root.appendingPathComponent("docs/images")

// Brand colours, also used in docs/index.html. Flat fills only: no gradients, no glows.
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

/// Draws into a bitmap of exactly `width` x `height` pixels (NSImage.lockFocus would double on Retina).
func render(_ width: Int, _ height: Int, _ draw: (CGRect) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(CGRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// The icon artwork in `canvas`, on the macOS grid: an 824/1024 rounded square in brand blue with a white
/// "R" (SF Pro Bold) and a text cursor (I-beam) of the same height.
func drawIcon(in canvas: CGRect) {
    let side = canvas.width * 824 / 1024
    let body = CGRect(x: canvas.midX - side / 2, y: canvas.midY - side / 2, width: side, height: side)
    let radius = side * 185 / 824
    let shape = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.15)
    shadow.shadowOffset = NSSize(width: 0, height: -side * 0.01)
    shadow.shadowBlurRadius = side * 0.025
    shadow.set()
    color(brandBlue).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

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

    // Optical centre: the group's ink box sits on the body's centre, nudged up 1% because a shape looks low at true centre.
    let originX = body.midX - total / 2 - ink.minX
    let originY = body.midY - capHeight / 2 + side * 0.01
    let path = CGMutablePath()
    path.addPath(letter, transform: CGAffineTransform(translationX: originX, y: originY))
    let beamX = originX + ink.maxX + gap
    path.addRect(CGRect(x: beamX + (beamWidth - stem) / 2, y: originY, width: stem, height: capHeight))
    path.addRect(CGRect(x: beamX, y: originY, width: beamWidth, height: bar))
    path.addRect(CGRect(x: beamX, y: originY + capHeight - bar, width: beamWidth, height: bar))

    let context = NSGraphicsContext.current!.cgContext
    context.addPath(path)
    context.setFillColor(NSColor.white.cgColor)
    context.fillPath(using: .winding)
}

func write(_ rep: NSBitmapImageRep, _ url: URL) {
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("Retext-\(UUID().uuidString)/AppIcon.iconset")
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try! FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
try! FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let name = factor == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        write(render(points * factor, points * factor, drawIcon), iconset.appendingPathComponent(name))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }

// Product Hunt thumbnail: the full rounded square, edge to edge.
write(render(240, 240) { rect in drawIcon(in: rect.insetBy(dx: -rect.width * 100 / 824, dy: -rect.height * 100 / 824)) },
      images.appendingPathComponent("icon-240.png"))

// Social preview (GitHub, Open Graph): icon, name and tagline on a flat background.
write(render(1280, 640) { rect in
    color(previewBackground).setFill()
    rect.fill()
    drawIcon(in: CGRect(x: 96, y: 160, width: 320, height: 320))
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

print("Wrote \(resources.path)/AppIcon.icns and docs/images/icon-240.png, social-preview.png")

// Renders the draft Retext app icon and the launch images. Usage: swift scripts/make-icon.swift
// Writes Resources/AppIcon.icns (16...512 pt at 1x and 2x, via a temporary iconset and iconutil),
// docs/images/icon-240.png (Product Hunt) and docs/images/social-preview.png (1280x640).
// A programmatic draft: replace Resources/AppIcon.icns with a designed icon when one exists.
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources")
let images = root.appendingPathComponent("docs/images")

let top = NSColor(srgbRed: 0.33, green: 0.56, blue: 1.00, alpha: 1)
let bottom = NSColor(srgbRed: 0.45, green: 0.32, blue: 0.93, alpha: 1)

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

/// The icon artwork in `canvas`, on the macOS grid: an 824/1024 rounded square with a white text-cursor glyph.
func drawIcon(in canvas: CGRect) {
    let side = canvas.width * 824 / 1024
    let body = CGRect(x: canvas.midX - side / 2, y: canvas.midY - side / 2, width: side, height: side)
    let radius = side * 185 / 824
    let shape = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -side * 0.012)
    shadow.shadowBlurRadius = side * 0.03
    shadow.set()
    bottom.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: top, ending: bottom)!.draw(in: shape, angle: -90)

    let config = NSImage.SymbolConfiguration(pointSize: side * 0.5, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    guard let symbol = NSImage(systemSymbolName: "character.cursor.ibeam", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else { fatalError("SF Symbol character.cursor.ibeam not found") }
    let scale = min(side * 0.58 / symbol.size.width, side * 0.58 / symbol.size.height)
    let size = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
    symbol.draw(in: CGRect(x: body.midX - size.width / 2, y: body.midY - size.height / 2, width: size.width, height: size.height))
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
    NSColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1).setFill()
    rect.fill()
    drawIcon(in: CGRect(x: 96, y: 160, width: 320, height: 320))
    let name = NSAttributedString(string: "Retext", attributes: [
        .font: NSFont.systemFont(ofSize: 112, weight: .bold),
        .foregroundColor: NSColor(srgbRed: 0.11, green: 0.11, blue: 0.13, alpha: 1),
    ])
    name.draw(at: CGPoint(x: 456, y: 324))
    let tagline = NSAttributedString(string: "Fix, translate and rewrite text\nin any Mac app", attributes: [
        .font: NSFont.systemFont(ofSize: 44, weight: .regular),
        .foregroundColor: NSColor(srgbRed: 0.36, green: 0.36, blue: 0.40, alpha: 1),
    ])
    tagline.draw(in: CGRect(x: 460, y: 170, width: 780, height: 140))
}, images.appendingPathComponent("social-preview.png"))

print("Wrote \(resources.path)/AppIcon.icns and docs/images/icon-240.png, social-preview.png")

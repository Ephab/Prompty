// Renders Prompty's app icon. Run via Scripts/make-icon.sh.
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

    // macOS icon grid: an 824pt squircle centred on the 1024 canvas.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

    ctx.saveGState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor.black.setFill()
    squircle.fill()
    ctx.restoreGState()

    ctx.saveGState()
    squircle.addClip()
    NSGradient(colors: [
        NSColor(srgbRed: 0.42, green: 0.30, blue: 0.98, alpha: 1),
        NSColor(srgbRed: 0.20, green: 0.42, blue: 0.98, alpha: 1),
        NSColor(srgbRed: 0.10, green: 0.62, blue: 0.95, alpha: 1),
    ])!.draw(in: tile, angle: -60)
    // Soft top sheen.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2), angle: -90)
    ctx.restoreGState()

    // A floating "card" — the prompt panel — in frosted white.
    let card = NSRect(x: 222, y: 300, width: 580, height: 424)
    let cardPath = NSBezierPath(roundedRect: card, xRadius: 74, yRadius: 74)
    ctx.saveGState()
    let cardShadow = NSShadow()
    cardShadow.shadowColor = NSColor(srgbRed: 0.05, green: 0.08, blue: 0.35, alpha: 0.35)
    cardShadow.shadowBlurRadius = 40
    cardShadow.shadowOffset = NSSize(width: 0, height: -18)
    cardShadow.set()
    NSColor.white.withAlphaComponent(0.96).setFill()
    cardPath.fill()
    ctx.restoreGState()

    // Prompt chevron and a text cursor.
    let ink = NSColor(srgbRed: 0.27, green: 0.30, blue: 0.92, alpha: 1)
    ink.setStroke()
    let chevron = NSBezierPath()
    chevron.lineWidth = 58
    chevron.lineCapStyle = .round
    chevron.lineJoinStyle = .round
    chevron.move(to: NSPoint(x: 330, y: 610))
    chevron.line(to: NSPoint(x: 440, y: 512))
    chevron.line(to: NSPoint(x: 330, y: 414))
    chevron.stroke()

    ink.withAlphaComponent(0.9).setFill()
    NSBezierPath(roundedRect: NSRect(x: 500, y: 400, width: 200, height: 52), xRadius: 26, yRadius: 26).fill()

    // A sparkle above the card for "ready to paste" energy.
    func sparkle(at c: NSPoint, r: CGFloat) {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: c.x, y: c.y + r))
        p.curve(to: NSPoint(x: c.x + r, y: c.y), controlPoint1: NSPoint(x: c.x + r * 0.12, y: c.y + r * 0.12), controlPoint2: NSPoint(x: c.x + r * 0.12, y: c.y + r * 0.12))
        p.curve(to: NSPoint(x: c.x, y: c.y - r), controlPoint1: NSPoint(x: c.x + r * 0.12, y: c.y - r * 0.12), controlPoint2: NSPoint(x: c.x + r * 0.12, y: c.y - r * 0.12))
        p.curve(to: NSPoint(x: c.x - r, y: c.y), controlPoint1: NSPoint(x: c.x - r * 0.12, y: c.y - r * 0.12), controlPoint2: NSPoint(x: c.x - r * 0.12, y: c.y - r * 0.12))
        p.curve(to: NSPoint(x: c.x, y: c.y + r), controlPoint1: NSPoint(x: c.x - r * 0.12, y: c.y + r * 0.12), controlPoint2: NSPoint(x: c.x - r * 0.12, y: c.y + r * 0.12))
        p.fill()
    }
    NSColor.white.setFill()
    sparkle(at: NSPoint(x: 760, y: 790), r: 70)
    NSColor.white.withAlphaComponent(0.75).setFill()
    sparkle(at: NSPoint(x: 660, y: 830), r: 30)
    return true
}

let outDir = CommandLine.arguments[1]
for (points, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for scale in scales {
        let px = points * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
    }
}

// Renders Resources/AppIcon.icns: Hoku's guiding star over a night sky, casting a
// soft cone of light downwards. Drawn from paths only (no SF Symbols, whose license
// doesn't allow use in app icons).
// Usage: swift scripts/make-icon.swift <output-dir>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = output.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

/// A four-pointed star with gently concave sides.
func starPath(center: NSPoint, radius: CGFloat, waist: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    for index in 0..<4 {
        let angle = CGFloat(index) * .pi / 2 + .pi / 2
        let tip = NSPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        let next = angle + .pi / 2
        let nextTip = NSPoint(x: center.x + cos(next) * radius, y: center.y + sin(next) * radius)
        let control = NSPoint(
            x: center.x + cos(angle + .pi / 4) * radius * waist,
            y: center.y + sin(angle + .pi / 4) * radius * waist
        )
        if index == 0 { path.move(to: tip) }
        path.curve(to: nextTip, controlPoint1: control, controlPoint2: control)
    }
    path.close()
    return path
}

func render(_ pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: ~80% body with rounded corners.
    let inset = size * 0.1
    let body = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let shape = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()

    // Night sky
    NSGradient(colors: [
        NSColor(red: 0.05, green: 0.06, blue: 0.18, alpha: 1),
        NSColor(red: 0.16, green: 0.12, blue: 0.36, alpha: 1),
        NSColor(red: 0.30, green: 0.17, blue: 0.42, alpha: 1),
    ])!.draw(in: body, angle: -90)

    // A faint, fixed starfield
    var seed: UInt64 = 0x484F_4B55
    func random() -> CGFloat {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return CGFloat(seed >> 33) / CGFloat(1 << 31)
    }
    for _ in 0..<38 {
        let point = NSPoint(x: body.minX + random() * body.width, y: body.minY + body.height * (0.35 + 0.65 * random()))
        let dot = max(size * 0.004, 0.6) * (0.6 + random())
        NSColor.white.withAlphaComponent(0.25 + 0.5 * random()).setFill()
        NSBezierPath(ovalIn: NSRect(x: point.x, y: point.y, width: dot, height: dot)).fill()
    }

    let center = NSPoint(x: body.midX, y: body.minY + body.height * 0.6)
    let warm = NSColor(red: 1, green: 0.78, blue: 0.42, alpha: 1)

    // Cone of light falling from the star into the "room" below
    let cone = NSBezierPath()
    cone.move(to: NSPoint(x: center.x - body.width * 0.06, y: center.y))
    cone.line(to: NSPoint(x: center.x + body.width * 0.06, y: center.y))
    cone.line(to: NSPoint(x: center.x + body.width * 0.42, y: body.minY))
    cone.line(to: NSPoint(x: center.x - body.width * 0.42, y: body.minY))
    cone.close()
    NSGradient(colors: [warm.withAlphaComponent(0.42), warm.withAlphaComponent(0.0)])!
        .draw(in: cone, angle: -90)

    // Glow
    let glowRadius = body.width * 0.42
    NSGradient(
        colors: [warm.withAlphaComponent(0.6), warm.withAlphaComponent(0.22), warm.withAlphaComponent(0.06), warm.withAlphaComponent(0)],
        atLocations: [0, 0.3, 0.65, 1],
        colorSpace: .deviceRGB
    )!.draw(in: NSBezierPath(ovalIn: NSRect(x: center.x - glowRadius, y: center.y - glowRadius, width: glowRadius * 2, height: glowRadius * 2)),
            relativeCenterPosition: .zero)

    // The star
    let star = starPath(center: center, radius: body.width * 0.29, waist: 0.2)
    NSGradient(colors: [
        NSColor(red: 1, green: 0.98, blue: 0.9, alpha: 1),
        warm,
    ])!.draw(in: star, relativeCenterPosition: .zero)

    // Liquid-glass sheen along the top edge
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: body.minX, y: body.maxY - body.height * 0.28, width: body.width, height: body.height * 0.28), angle: -90)

    NSGraphicsContext.restoreGraphicsState()

    // Thin rim
    NSColor.white.withAlphaComponent(0.12).setStroke()
    shape.lineWidth = max(size * 0.004, 1)
    shape.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

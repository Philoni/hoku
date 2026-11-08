import AppKit

/// Draws the status item icon: a plain template bulb when everything is off, and a
/// bulb filled with the colors of the lights that are on (with a soft halo) otherwise.
enum MenuBarIcon {
    static func image(colors: [NSColor]) -> NSImage {
        guard !colors.isEmpty else {
            let off = NSImage(systemSymbolName: "lightbulb", accessibilityDescription: "Hoku")!
                .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))!
            off.isTemplate = true
            return off
        }

        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        guard let filled = NSImage(systemSymbolName: "lightbulb.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration),
              let outline = NSImage(systemSymbolName: "lightbulb", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        else { return NSImage() }

        let symbolSize = filled.size
        let canvas = NSSize(width: symbolSize.width + 6, height: 18)
        let image = NSImage(size: canvas, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let symbolRect = NSRect(
                x: (rect.width - symbolSize.width) / 2,
                y: (rect.height - symbolSize.height) / 2,
                width: symbolSize.width,
                height: symbolSize.height
            )

            // Halo
            let halo = NSGradient(colors: [colors[0].withAlphaComponent(0.55), colors[0].withAlphaComponent(0)])
            halo?.draw(in: NSBezierPath(ovalIn: rect.insetBy(dx: -1, dy: -1)), relativeCenterPosition: NSPoint(x: 0, y: 0.15))

            // Bulb filled with the light colors, using the symbol as a mask.
            if let mask = filled.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                context.saveGState()
                context.clip(to: symbolRect, mask: mask)
                let stops = colors.count == 1 ? [colors[0], colors[0]] : Array(colors.prefix(4))
                NSGradient(colors: stops)?.draw(in: symbolRect, angle: -90)
                context.restoreGState()
            }

            // Outline in the menu bar's text color keeps it legible on any wallpaper.
            if let mask = outline.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                context.saveGState()
                context.clip(to: symbolRect, mask: mask)
                NSColor.labelColor.withAlphaComponent(0.85).setFill()
                symbolRect.fill()
                context.restoreGState()
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Hoku – Lichter an"
        return image
    }
}

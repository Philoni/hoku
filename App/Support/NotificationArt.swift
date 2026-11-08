import AppKit
import SwiftUI

/// The picture beside the "Zu Hause brennt noch Licht" notification: the lamps that
/// are on, as soft glows around a bulb, in the same spirit as the panel's background.
struct NotificationArt: View {
    let colors: [Color]

    /// Where the glows sit for one to five lamps: centered alone, spread when several.
    /// macOS shows the picture small, so the glows fill it and the bulb stays modest.
    private static func spots(_ count: Int) -> [CGPoint] {
        switch count {
        case 1: [.zero]
        case 2: [CGPoint(x: -24, y: -18), CGPoint(x: 24, y: 18)]
        case 3: [CGPoint(x: -26, y: -20), CGPoint(x: 26, y: -14), CGPoint(x: 0, y: 28)]
        default: [CGPoint(x: -28, y: -24), CGPoint(x: 28, y: -20), CGPoint(x: -24, y: 26), CGPoint(x: 26, y: 28), .zero]
        }
    }

    var body: some View {
        let shown = Array(colors.prefix(5))
        let spots = Self.spots(shown.count)
        ZStack {
            Color(red: 0.10, green: 0.09, blue: 0.15)
            ForEach(Array(shown.enumerated()), id: \.offset) { index, color in
                Circle()
                    .fill(color)
                    .frame(width: shown.count == 1 ? 150 : 110, height: shown.count == 1 ? 150 : 110)
                    .blur(radius: 28)
                    .offset(x: spots[index].x, y: spots[index].y)
            }
            Image(systemName: "lightbulb.max.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .white.opacity(0.6), radius: 8)
        }
        .frame(width: 160, height: 160)
    }

    /// Renders to a temporary PNG; the notification center moves the file into its own store.
    @MainActor
    static func png(colors: [Color]) -> URL? {
        let renderer = ImageRenderer(content: NotificationArt(colors: colors))
        renderer.scale = 2
        guard let image = renderer.cgImage else { return nil }
        let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        let url = URL.temporaryDirectory.appending(path: "hoku-lights-\(UUID().uuidString).png")
        do { try data?.write(to: url) } catch { return nil }
        return data == nil ? nil : url
    }
}

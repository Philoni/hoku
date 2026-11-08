import AppKit
import SwiftUI

enum Theme {
    static let cardRadius: CGFloat = 16
    static let width: CGFloat = 320
    // Explicit, non-vibrant colors (vibrant system fills turn black while views
    // animate), each with a dark-glass and a light-glass variant.
    /// "A window at night" in dark mode, frosted glass in light mode.
    static let tile = Adaptive(dark: .black.opacity(0.34), light: .white.opacity(0.55))
    static let tileStroke = Adaptive(dark: .white.opacity(0.07), light: .black.opacity(0.07))
    static let control = Adaptive(dark: .white.opacity(0.12), light: .black.opacity(0.07))
    static let text = Adaptive(dark: .white, light: .black.opacity(0.85))
    static let faint = Adaptive(dark: .white.opacity(0.45), light: .black.opacity(0.35))
    static let ring = Adaptive(dark: .white.opacity(0.85), light: .black.opacity(0.6))
    static let switchOff = Adaptive(dark: .white.opacity(0.16), light: .black.opacity(0.12))
    static let selectedChip = Adaptive(dark: .white.opacity(0.92), light: .black.opacity(0.78))
    static let selectedChipText = Adaptive(dark: .black.opacity(0.8), light: .white)
    static let nightLight: [Color] = [
        Color(red: 0.80, green: 0.84, blue: 0.95),
        Color(red: 0.92, green: 0.86, blue: 0.95),
        Color(red: 0.84, green: 0.90, blue: 0.94),
    ]
    static let spring = Animation.spring(response: 0.36, dampingFraction: 0.8)
    /// A filament cooling down, for the "all off" afterglow.
    static let embers = [
        Color(red: 0.95, green: 0.38, blue: 0.12),
        Color(red: 0.72, green: 0.18, blue: 0.08),
    ]
    /// The keyboard focus ring gliding between cards: quick, with a hint of overshoot.
    static let focusSpring = Animation.spring(response: 0.3, dampingFraction: 0.78)
    static let softSpring = Animation.spring(response: 0.48, dampingFraction: 0.88)
    static let night: [Color] = [
        Color(red: 0.10, green: 0.10, blue: 0.22),
        Color(red: 0.18, green: 0.12, blue: 0.30),
        Color(red: 0.08, green: 0.14, blue: 0.26),
    ]
}

/// A color that picks its dark or light variant from the environment's color scheme
/// (which follows the panel's appearance).
struct Adaptive: ShapeStyle {
    let dark: Color
    let light: Color

    func resolve(in environment: EnvironmentValues) -> Color {
        environment.colorScheme == .dark ? dark : light
    }
}

/// Trackpad haptics for toggles and slider limits.
@MainActor
enum Haptics {
    static func tap() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    static func edge() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}

extension Color {
    var luminance: Double {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return 0.5 }
        return 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
    }
}

extension Array where Element == Color {
    /// Readable text color on top of a gradient of these colors.
    var contrastingText: Color {
        let average = isEmpty ? 0 : map(\.luminance).reduce(0, +) / Double(count)
        return average > 0.5 ? .black.opacity(0.8) : .white
    }

    /// At least two stops, so gradients never degenerate.
    var gradientStops: [Color] {
        switch count {
        case 0: [.yellow, .orange]
        case 1: [self[0], self[0].opacity(0.85)]
        default: self
        }
    }
}

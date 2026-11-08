import SwiftUI

/// Slowly drifting mesh gradient in the colors of the lights that are on.
struct AmbientBackground: View {
    let colors: [Color]
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isPanelVisible) private var isPanelVisible

    var body: some View {
        let isDark = colorScheme == .dark
        let palette = colors.isEmpty ? (isDark ? Theme.night : Theme.nightLight) : colors
        // A slow drift under a heavy blur: 15 frames a second look the same as 30.
        TimelineView(.animation(minimumInterval: 1 / 15, paused: !isPanelVisible)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            MeshGradient(
                width: 3,
                height: 3,
                points: Self.points(t),
                colors: (0..<9).map { palette[$0 % palette.count] }
            )
        }
        .blur(radius: 40)
        .opacity(colors.isEmpty ? (isDark ? 0.5 : 0.35) : (isDark ? 0.38 : 0.3))
        .animation(.easeInOut(duration: 1.2), value: colors)
        .allowsHitTesting(false)
    }

    private static func points(_ t: Double) -> [SIMD2<Float>] {
        func wobble(_ base: Float, _ speed: Double, _ phase: Double) -> Float {
            base + Float(sin(t * speed + phase)) * 0.12
        }
        return [
            [0, 0], [0.5, 0], [1, 0],
            [0, wobble(0.5, 0.31, 0)], [wobble(0.5, 0.23, 1), wobble(0.5, 0.27, 2)], [1, wobble(0.5, 0.19, 3)],
            [0, 1], [wobble(0.5, 0.21, 4), 1], [1, 1],
        ]
    }
}

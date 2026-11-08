import SwiftUI

/// A small sky behind the greeting, matching the time of day: dawn with a rising sun,
/// blue day, sunset, and at night twinkling stars, a crescent moon and the odd
/// shooting star. It fades out downwards into the panel.
struct SkyView: View {
    let phase: DayPhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isSnapshot) private var isSnapshot
    @Environment(\.isPanelVisible) private var isPanelVisible

    var body: some View {
        ZStack {
            LinearGradient(colors: skyColors, startPoint: .top, endPoint: .bottom)
            switch phase {
            case .night:
                if isSnapshot {
                    StarField(time: 0)
                } else {
                    TimelineView(.animation(minimumInterval: 1 / 20, paused: !isPanelVisible)) { context in
                        StarField(time: context.date.timeIntervalSinceReferenceDate)
                    }
                }
                Moon()
                    .frame(width: 18, height: 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 14)
                    .padding(.trailing, 132)
            case .morning, .day, .evening:
                Sun(phase: phase)
            }
        }
        .opacity(colorScheme == .dark ? 0.8 : 0.6)
        .mask(LinearGradient(colors: [.black, .black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var skyColors: [Color] {
        switch phase {
        case .morning:
            [Color(red: 0.24, green: 0.28, blue: 0.55), Color(red: 0.93, green: 0.55, blue: 0.48), Color(red: 1, green: 0.78, blue: 0.52)]
        case .day:
            [Color(red: 0.22, green: 0.5, blue: 0.88), Color(red: 0.52, green: 0.76, blue: 0.97)]
        case .evening:
            [Color(red: 0.24, green: 0.15, blue: 0.42), Color(red: 0.82, green: 0.36, blue: 0.36), Color(red: 1, green: 0.6, blue: 0.32)]
        case .night:
            [Color(red: 0.02, green: 0.04, blue: 0.14), Color(red: 0.07, green: 0.09, blue: 0.26)]
        }
    }
}

private struct Sun: View {
    let phase: DayPhase

    var body: some View {
        GeometryReader { geometry in
            // Low on the horizon in the morning and evening, high at noon.
            let position: CGPoint = switch phase {
            case .morning: CGPoint(x: geometry.size.width * 0.18, y: geometry.size.height * 0.62)
            case .evening: CGPoint(x: geometry.size.width * 0.62, y: geometry.size.height * 0.66)
            default: CGPoint(x: geometry.size.width * 0.52, y: geometry.size.height * 0.24)
            }
            let glow: Color = phase == .day ? Color(red: 1, green: 0.9, blue: 0.55) : Color(red: 1, green: 0.66, blue: 0.3)
            ZStack {
                Circle().fill(glow.opacity(0.45)).frame(width: 80, height: 80).blur(radius: 20)
                Circle().fill(glow.opacity(0.7)).frame(width: 30, height: 30).blur(radius: 6)
                Circle()
                    .fill(RadialGradient(colors: [.white, glow], center: .center, startRadius: 0, endRadius: 10))
                    .frame(width: 16, height: 16)
            }
            .position(position)
        }
    }
}

private struct Moon: View {
    var body: some View {
        ZStack {
            Circle().fill(Color(red: 1, green: 0.97, blue: 0.86)).shadow(color: .white.opacity(0.6), radius: 6)
            Circle()
                .fill(Color(red: 0.03, green: 0.05, blue: 0.16))
                .offset(x: 5, y: -3)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
    }
}

/// Deterministic stars that twinkle, plus a shooting star every 14 seconds.
private struct StarField: View {
    let time: Double

    private static let stars: [(x: Double, y: Double, size: Double, speed: Double, phase: Double)] = {
        var seed: UInt64 = 0x1C47_B11C
        func random() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 33) / Double(1 << 31)
        }
        return (0..<46).map { _ in
            (x: random(), y: random() * 0.85, size: 0.6 + random() * 1.4, speed: 0.6 + random() * 1.8, phase: random() * 6.28)
        }
    }()

    var body: some View {
        Canvas { context, size in
            for star in Self.stars {
                let twinkle = 0.45 + 0.55 * (0.5 + 0.5 * sin(time * star.speed + star.phase))
                let rect = CGRect(x: star.x * size.width, y: star.y * size.height, width: star.size, height: star.size)
                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(twinkle)))
            }

            // Shooting star: visible for 0.9 s out of every 14 s.
            let period = 14.0
            let progress = (time.truncatingRemainder(dividingBy: period)) / 0.9
            guard progress < 1, time > 0 else { return }
            let cycle = Int(time / period)
            let startX = size.width * (0.15 + Double(cycle % 5) * 0.12)
            let start = CGPoint(x: startX, y: size.height * 0.08)
            let head = CGPoint(x: start.x + 120 * progress, y: start.y + 45 * progress)
            let tail = CGPoint(x: head.x - 36, y: head.y - 13.5)
            var path = Path()
            path.move(to: tail)
            path.addLine(to: head)
            context.stroke(
                path,
                with: .linearGradient(Gradient(colors: [.clear, .white.opacity(0.9 * (1 - progress))]), startPoint: tail, endPoint: head),
                lineWidth: 1.4
            )
        }
    }
}

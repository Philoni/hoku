import SwiftUI

// The setup's look: Hoku's star over a night sky. The star grows brighter with every
// step, and the steps light up one by one as a small constellation.

/// The four-pointed star of Hoku's icon.
struct FourPointStar: Shape {
    /// How far the concave sides pull in (0 = thin rays, 1 = a square).
    var waist: CGFloat = 0.32

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        for index in 0..<4 {
            let angle = CGFloat(index) * .pi / 2 - .pi / 2
            let tip = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            let nextAngle = angle + .pi / 2
            let nextTip = CGPoint(x: center.x + cos(nextAngle) * radius, y: center.y + sin(nextAngle) * radius)
            let control = CGPoint(
                x: center.x + cos(angle + .pi / 4) * radius * waist,
                y: center.y + sin(angle + .pi / 4) * radius * waist
            )
            if index == 0 { path.move(to: tip) }
            path.addCurve(to: nextTip, control1: control, control2: control)
        }
        path.closeSubpath()
        return path
    }
}

/// Hoku's star with a soft halo that breathes slowly. `brightness` 0…1.
struct HokuStar: View {
    var tint: Color
    var brightness: Double
    var size: CGFloat = 56
    /// Bump to make the star flare once (a step was completed).
    var flare = 0
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        Group {
            if isSnapshot {
                star(time: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 20)) { context in
                    star(time: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .keyframeAnimator(initialValue: 1.0, trigger: flare) { view, scale in
            view.scaleEffect(scale)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(1.18, duration: 0.18)
                SpringKeyframe(1.0, duration: 0.6, spring: .bouncy)
            }
        }
        .animation(.easeInOut(duration: 0.8), value: tint)
        .animation(.easeInOut(duration: 0.8), value: brightness)
        .accessibilityHidden(true)
    }

    private func star(time t: Double) -> some View {
        let breath = 0.5 + 0.5 * sin(t * 1.1)
        return ZStack {
            // A soft halo that fades out smoothly, warm-white at the core.
            Circle()
                .fill(RadialGradient(
                    colors: [
                        tint.mix(with: .white, by: 0.4).opacity(0.38 * brightness),
                        tint.opacity(0.16 * brightness),
                        tint.opacity(0.05 * brightness),
                        .clear,
                    ],
                    center: .center, startRadius: 0, endRadius: size * 1.6
                ))
                .frame(width: size * 3.2, height: size * 3.2)
                .scaleEffect(0.92 + 0.08 * breath)
            // Faint diagonal glints: the sparkle of a real star.
            ForEach([45.0, 135.0], id: \.self) { angle in
                Capsule()
                    .fill(LinearGradient(colors: [.clear, .white.opacity(0.55 * brightness), .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(width: size * (1.8 + 0.5 * breath), height: 1.2)
                    .rotationEffect(.degrees(angle))
            }
            FourPointStar()
                .fill(LinearGradient(colors: [.white, tint.mix(with: .white, by: 0.35)], startPoint: .top, endPoint: .bottom))
                .frame(width: size, height: size)
                .shadow(color: tint.opacity(0.9), radius: 10 + 8 * brightness)
                .shadow(color: .white.opacity(0.5), radius: 2)
        }
    }
}

/// A night sky with depth: two layers of stars turning very slowly, a faint band of
/// the Milky Way, now and then a shooting star, and hills against a horizon that
/// glows in the current step's color. Still when "Reduce motion" is on.
struct WizardBackdrop: View {
    var tint: Color
    @Environment(\.isSnapshot) private var isSnapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Star {
        var x, y, size, speed, phase: Double
    }

    private static func makeStars(count: Int, seed start: UInt64, sizes: ClosedRange<Double>) -> [Star] {
        var seed = start
        func random() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 33) / Double(1 << 31)
        }
        return (0..<count).map { _ in
            Star(x: random(), y: random() * 0.82, size: sizes.lowerBound + random() * (sizes.upperBound - sizes.lowerBound),
                 speed: 0.4 + random() * 1.4, phase: random() * 6.28)
        }
    }

    /// Far stars: many, tiny, dim. Near stars: few, brighter, the brightest get glints.
    private static let far = makeStars(count: 130, seed: 0x484F_4B55, sizes: 0.4...1.1)
    private static let near = makeStars(count: 34, seed: 0x5354_4152, sizes: 1.2...2.4)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.03, blue: 0.10),
                    Color(red: 0.06, green: 0.05, blue: 0.17),
                    Color(red: 0.12, green: 0.07, blue: 0.20),
                ],
                startPoint: .top, endPoint: .bottom
            )
            milkyWay
            if isSnapshot || reduceMotion {
                sky(time: 1)
            } else {
                // 24 fps is plenty for slow twinkling; the GPU composites the layer.
                TimelineView(.animation(minimumInterval: 1 / 24)) { context in
                    sky(time: context.date.timeIntervalSinceReferenceDate)
                }
                .drawingGroup()
            }
            // The horizon: light rising from below in the step's color, behind the hills.
            // Many soft stops instead of three: no visible rings in the glow.
            RadialGradient(
                stops: [
                    .init(color: tint.opacity(0.48), location: 0),
                    .init(color: tint.opacity(0.32), location: 0.18),
                    .init(color: tint.opacity(0.18), location: 0.38),
                    .init(color: tint.opacity(0.08), location: 0.6),
                    .init(color: tint.opacity(0.025), location: 0.82),
                    .init(color: .clear, location: 1),
                ],
                center: .bottom, startRadius: 0, endRadius: 460
            )
                .blendMode(.plusLighter)
                .animation(.easeInOut(duration: 1.0), value: tint)
            Hills(tint: tint)
                .frame(height: 96)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// A soft diagonal haze, as the Milky Way looks away from city lights.
    /// An overlay on a clear view, so its wide ellipses never widen the layout.
    private var milkyWay: some View {
        Color.clear.overlay {
            ZStack {
                Ellipse().fill(Color(red: 0.55, green: 0.5, blue: 0.95).opacity(0.10)).frame(width: 760, height: 140).blur(radius: 46)
                Ellipse().fill(Color(red: 0.95, green: 0.7, blue: 0.85).opacity(0.06)).frame(width: 420, height: 70).blur(radius: 30).offset(x: 60, y: 10)
            }
            .rotationEffect(.degrees(-24))
            .offset(y: -120)
        }
        .blendMode(.plusLighter)
    }

    private func sky(time: Double) -> some View {
        Canvas { canvas, size in
            // The sky turns: far stars a little slower than near ones, for depth.
            let drift = time.truncatingRemainder(dividingBy: 2400)
            draw(Self.far, in: &canvas, size: size, shift: drift * 0.25, brightness: 0.6, time: time)
            draw(Self.near, in: &canvas, size: size, shift: drift * 0.45, brightness: 0.95, time: time)
            if !isSnapshot && !reduceMotion { shootingStar(in: &canvas, size: size, time: time) }
        }
    }

    private func draw(_ stars: [Star], in canvas: inout GraphicsContext, size: CGSize, shift: Double, brightness: Double, time: Double) {
        for star in stars {
            let twinkle = 0.35 + 0.65 * (0.5 + 0.5 * sin(time * star.speed + star.phase))
            let x = (star.x * size.width + shift).truncatingRemainder(dividingBy: size.width)
            let y = star.y * size.height
            let opacity = brightness * twinkle
            canvas.fill(Path(ellipseIn: CGRect(x: x, y: y, width: star.size, height: star.size)), with: .color(.white.opacity(opacity)))
            // The brightest near stars get a faint cross of light.
            if star.size > 2.1 {
                let center = CGPoint(x: x + star.size / 2, y: y + star.size / 2)
                let length = star.size * 3.2 * twinkle
                var glint = Path()
                glint.move(to: CGPoint(x: center.x - length, y: center.y)); glint.addLine(to: CGPoint(x: center.x + length, y: center.y))
                glint.move(to: CGPoint(x: center.x, y: center.y - length)); glint.addLine(to: CGPoint(x: center.x, y: center.y + length))
                canvas.stroke(glint, with: .color(.white.opacity(opacity * 0.35)), lineWidth: 0.6)
            }
        }
    }

    /// Every 11 seconds one streak, somewhere else each time, gone within a second.
    private func shootingStar(in canvas: inout GraphicsContext, size: CGSize, time: Double) {
        let period = 11.0, duration = 0.9
        let cycle = floor(time / period)
        let age = time - cycle * period
        guard age < duration else { return }
        var seed = UInt64(abs(cycle.truncatingRemainder(dividingBy: 10_000))) &+ 7
        func random() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 33) / Double(1 << 31)
        }
        let start = CGPoint(x: size.width * (0.15 + 0.6 * random()), y: size.height * (0.06 + 0.22 * random()))
        let travel = CGVector(dx: size.width * 0.32, dy: size.height * 0.13)
        let progress = age / duration
        let eased = 1 - pow(1 - progress, 2.2)
        let head = CGPoint(x: start.x + travel.dx * eased, y: start.y + travel.dy * eased)
        let tail = CGPoint(x: head.x - travel.dx * 0.28, y: head.y - travel.dy * 0.28)
        let fade = progress < 0.2 ? progress / 0.2 : 1 - (progress - 0.2) / 0.8
        var streak = Path()
        streak.move(to: tail)
        streak.addLine(to: head)
        canvas.stroke(
            streak,
            with: .linearGradient(Gradient(colors: [.clear, .white.opacity(0.85 * fade)]), startPoint: tail, endPoint: head),
            style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
        )
    }
}

/// Two soft ranges of hills against the horizon glow, the nearer one darker.
private struct Hills: View {
    var tint: Color

    private static let back: [CGFloat] = [0.55, 0.3, 0.62, 0.4, 0.7, 0.35, 0.5]
    private static let front: [CGFloat] = [0.25, 0.42, 0.2, 0.36, 0.18, 0.3, 0.22]

    var body: some View {
        ZStack(alignment: .bottom) {
            Ridge(peaks: Self.back)
                .fill(Color(red: 0.07, green: 0.06, blue: 0.14).opacity(0.85))
                .overlay(Ridge(peaks: Self.back, closed: false).stroke(tint.opacity(0.22), lineWidth: 1))
            Ridge(peaks: Self.front)
                .fill(Color(red: 0.03, green: 0.03, blue: 0.08))
        }
        .animation(.easeInOut(duration: 1.0), value: tint)
    }
}

/// A smooth line through evenly spaced peaks (0 = bottom, 1 = top), closed to the
/// bottom edge for filling, or open for the rim light along the top.
private struct Ridge: Shape {
    var peaks: [CGFloat]
    var closed = true

    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ peak: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.maxY - peak * rect.height)
        }
        return Path { path in
            if closed { path.move(to: CGPoint(x: rect.minX, y: rect.maxY)); path.addLine(to: point(0, peaks[0])) }
            else { path.move(to: point(0, peaks[0])) }
            for index in 1..<peaks.count {
                let x0 = CGFloat(index - 1) / CGFloat(peaks.count - 1)
                let x1 = CGFloat(index) / CGFloat(peaks.count - 1)
                let mid = (x0 + x1) / 2
                path.addCurve(to: point(x1, peaks[index]), control1: point(mid, peaks[index - 1]), control2: point(mid, peaks[index]))
            }
            if closed { path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); path.closeSubpath() }
        }
    }
}

/// Progress as a constellation: done steps are lit stars joined by lines, the current
/// one pulses, the rest wait as faint dots.
struct ConstellationProgress: View {
    let count: Int
    let current: Int
    let completed: Set<Int>
    var tint: Color

    /// A gentle, asymmetric zig-zag, so it reads as a constellation rather than dots.
    private static let heights: [CGFloat] = [0.55, 0.15, 0.4, 0.0, 0.62, 0.3, 0.85, 0.45, 0.7]

    var body: some View {
        GeometryReader { geometry in
            let points = (0..<count).map { index in
                CGPoint(
                    x: count > 1 ? geometry.size.width * CGFloat(index) / CGFloat(count - 1) : geometry.size.width / 2,
                    y: geometry.size.height * Self.heights[index % Self.heights.count]
                )
            }
            ZStack {
                ForEach(0..<max(count - 1, 0), id: \.self) { index in
                    let lit = completed.contains(index) && (completed.contains(index + 1) || index + 1 == current)
                    Path { path in
                        path.move(to: points[index])
                        path.addLine(to: points[index + 1])
                    }
                    .trim(from: 0, to: lit ? 1 : 0)
                    .stroke(tint.opacity(0.75), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                    .shadow(color: tint, radius: 3)
                    .background {
                        Path { path in
                            path.move(to: points[index])
                            path.addLine(to: points[index + 1])
                        }
                        .stroke(.white.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    }
                    .animation(.easeInOut(duration: 0.6), value: lit)
                }
                ForEach(0..<count, id: \.self) { index in
                    node(isDone: completed.contains(index), isCurrent: index == current)
                        .position(points[index])
                }
            }
        }
        .frame(width: CGFloat(max(count - 1, 1)) * 26, height: 22)
        .accessibilityElement()
        .accessibilityLabel("Schritt \(current + 1) von \(count)")
    }

    @ViewBuilder
    private func node(isDone: Bool, isCurrent: Bool) -> some View {
        ZStack {
            if isCurrent {
                Circle()
                    .stroke(tint.opacity(0.7), lineWidth: 1)
                    .frame(width: 13, height: 13)
                    .phaseAnimator([0.8, 1.25]) { ring, scale in
                        ring.scaleEffect(scale).opacity(1.6 - scale)
                    } animation: { _ in .easeInOut(duration: 1.2) }
            }
            FourPointStar()
                .fill(isDone || isCurrent ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.25)))
                .frame(width: isDone || isCurrent ? 9 : 6, height: isDone || isCurrent ? 9 : 6)
                .shadow(color: isDone || isCurrent ? tint : .clear, radius: 4)
        }
        .animation(Theme.spring, value: isDone)
        .animation(Theme.spring, value: isCurrent)
    }
}

/// A step's parts arrive one after another, drifting up out of a soft blur, instead of
/// the whole step appearing at once. With "Reduce motion" they only fade.
struct WizardAppear: ViewModifier {
    let index: Int
    @Environment(\.isSnapshot) private var isSnapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    func body(content: Content) -> some View {
        let shown = isVisible || isSnapshot
        return content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 12)
            .blur(radius: shown || reduceMotion ? 0 : 6)
            .onAppear {
                withAnimation(Theme.softSpring.delay(0.06 + Double(min(index, 8)) * 0.07)) { isVisible = true }
            }
    }
}

extension View {
    func wizardAppear(_ index: Int) -> some View {
        modifier(WizardAppear(index: index))
    }
}

// MARK: - Buttons and cards

struct WizardPrimaryButtonStyle: ButtonStyle {
    var tint: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14.5, weight: .semibold, design: .rounded))
            .foregroundStyle(.black.opacity(isEnabled ? 0.82 : 0.45))
            .padding(.horizontal, 22)
            .frame(height: 42)
            .background {
                Capsule()
                    .fill(LinearGradient(colors: [tint.mix(with: .white, by: 0.25), tint], startPoint: .top, endPoint: .bottom))
                    .opacity(isEnabled ? 1 : 0.4)
            }
            .shadow(color: tint.opacity(isEnabled ? 0.55 : 0), radius: configuration.isPressed ? 6 : 14, y: 2)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Theme.spring, value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.4), value: tint)
    }
}

struct WizardQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.45 : 0.72))
            .padding(.horizontal, 12)
            .frame(height: 42)
            .contentShape(Capsule())
    }
}

/// A frosted card on the night sky.
struct WizardCard<Content: View>: View {
    var tint: Color = .white
    var padding: CGFloat = 14
    /// Position in the step's arrival order (the header is 0).
    var appear = 1
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(0.06))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(LinearGradient(colors: [tint.opacity(0.10), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    }
            }
            .wizardAppear(appear)
    }
}

/// A big two-option answer, used for the voice questions.
struct WizardChoiceButton: View {
    let title: String
    var subtitle: String?
    let systemImage: String
    var isSuggested = false
    var tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 14.5, weight: .semibold, design: .rounded))
                    if let subtitle {
                        Text(subtitle).font(.system(size: 12.5, design: .rounded)).foregroundStyle(.white.opacity(0.62))
                    }
                }
                Spacer(minLength: 0)
                if isSuggested {
                    Text("Erkannt")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(tint.opacity(0.25)))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 58)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(isSuggested ? 0.1 : 0.06))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isSuggested ? tint.opacity(0.6) : .white.opacity(0.1), lineWidth: 1)
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

/// Keyboard keys, drawn like real keycaps.
struct Keycaps: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(minWidth: 34, minHeight: 34)
                    .padding(.horizontal, 4)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.07)], startPoint: .top, endPoint: .bottom))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1))
                            .shadow(color: .black.opacity(0.4), radius: 0, y: 2)
                    }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(keys.joined(separator: " "))
    }
}

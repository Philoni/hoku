import SwiftUI

/// The signature control, "a window at night": a dark tile that lights up from
/// within. The fill is the brightness slider, and the whole tile glows brighter as
/// the brightness rises. Drag anywhere to dim, tap to open, switch to toggle.
struct SliderCard<Label: View>: View {
    let value: Double
    let isOn: Bool
    let colors: [Color]
    var height: CGFloat = 54
    var cornerRadius: CGFloat = Theme.cardRadius
    /// Smaller switch and padding, for lamp rows inside an expanded room card.
    var isCompact = false
    var isDimmable = true
    let onToggle: () -> Void
    let onBrightness: (Double) -> Void
    var onOpen: (() -> Void)?
    /// Relative dimming (swipe gestures, keyboard). Reads the live value when called.
    var onAdjust: ((Double) -> Void)?
    /// Lets "all off" ripple through the cards one after another.
    var animationDelay: Double = 0
    /// While "all off" runs: switching off lets the fill fade out in ember tones,
    /// like a filament cooling down, instead of sliding away.
    var afterglow = false
    @ViewBuilder let label: (_ liveValue: Double?) -> Label

    @State private var dragValue: Double?
    @State private var isPressed = false
    @State private var isHovering = false
    @State private var hoverID = UUID()

    var body: some View {
        let shown = dragValue ?? value
        let showsFill = isOn || dragValue != nil
        let isCooling = afterglow && !isOn && dragValue == nil
        let level = isDimmable ? min(max(shown / 100, 0), 1) : 1
        let fraction = showsFill || isCooling ? level : 0
        let stops = colors.gradientStops
        let textOnFill = stops.contrastingText
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let inset: CGFloat = isCompact ? 10 : 12

        GeometryReader { geometry in
            let fillWidth = geometry.size.width * fraction
            // The fill ends in the card's own curve, so it never shows a hard edge.
            let endRadius = min(cornerRadius, fillWidth / 2, geometry.size.height / 2)
            let fillShape = UnevenRoundedRectangle(
                bottomTrailingRadius: endRadius,
                topTrailingRadius: endRadius,
                style: .continuous
            )

            ZStack(alignment: .leading) {
                shape.fill(Theme.tile)

                // The room's glow, growing with brightness.
                RadialGradient(
                    colors: [stops[0], stops[stops.count - 1].opacity(0.55), .clear],
                    center: UnitPoint(x: 0.08, y: 0.5),
                    startRadius: 0,
                    endRadius: geometry.size.width * 1.05
                )
                .opacity(showsFill ? 0.22 + 0.5 * fraction : 0)

                LinearGradient(colors: stops, startPoint: .leading, endPoint: .trailing)
                    .overlay {
                        LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center)
                    }
                    .overlay {
                        LinearGradient(colors: Theme.embers, startPoint: .leading, endPoint: .trailing)
                            .opacity(isCooling ? 0.9 : 0)
                            .animation(isCooling ? .easeOut(duration: 0.3).delay(animationDelay) : nil, value: isCooling)
                    }
                    .clipShape(fillShape)
                    .frame(width: fillWidth)
                    .opacity(isCooling ? 0 : 1)
                    // Fade out slowly; once cold, reset at once so nothing slides back.
                    .animation(isCooling ? .easeIn(duration: 1.4).delay(animationDelay) : nil, value: isCooling)

                // Label, twice: light on the dark tile, and masked to the fill in a color
                // that reads on it, so the text switches color exactly at the edge.
                HStack(spacing: isCompact ? 8 : 10) {
                    ZStack(alignment: .leading) {
                        label(dragValue)
                            .foregroundStyle(Theme.text)
                        label(dragValue)
                            .foregroundStyle(textOnFill)
                            .mask(alignment: .leading) {
                                Rectangle().frame(width: max((isCooling ? 0 : fillWidth) - inset, 0))
                            }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if onOpen != nil {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.faint)
                            .opacity(isHovering ? 1 : 0)
                    }

                    GlowSwitch(isOn: isOn, tint: stops[0], isCompact: isCompact, action: onToggle)
                }
                .padding(.horizontal, inset)
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(showsFill ? AnyShapeStyle(.white.opacity(0.14)) : AnyShapeStyle(Theme.tileStroke), lineWidth: 1))
            .contentShape(shape)
            .gesture(dragGesture(width: geometry.size.width))
        }
        .frame(height: height)
        .brightness(isHovering && dragValue == nil ? 0.035 : 0)
        .shadow(color: stops[0].opacity(showsFill ? 0.18 + 0.25 * fraction : 0), radius: isHovering ? 14 : 10, y: 2)
        .scaleEffect(dragValue != nil ? 1.015 : (isPressed ? 0.975 : (isHovering ? 1.008 : 1)))
        .animation(Theme.spring.delay(animationDelay), value: isOn)
        .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.86), value: dragValue)
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.85), value: value)
        .animation(Theme.spring, value: isPressed)
        .animation(.easeOut(duration: 0.18), value: isHovering)
        .animation(.easeInOut(duration: 0.5), value: colors)
        .onHover { hovering in
            isHovering = hovering
            guard isDimmable, let onAdjust else { return }
            if hovering {
                HoverDimming.shared.enter(hoverID, adjust: onAdjust)
            } else {
                HoverDimming.shared.leave(hoverID)
            }
        }
        .onDisappear { HoverDimming.shared.leave(hoverID) }
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                let isDrag = abs(gesture.translation.width) > 4 || dragValue != nil
                guard isDrag, isDimmable else {
                    isPressed = true
                    return
                }
                isPressed = false
                let newValue = min(max((gesture.location.x / width * 100).rounded(), 1), 100)
                if newValue != dragValue {
                    // Felt detents at the ends and at every quarter.
                    let previous = dragValue ?? value
                    let crossesQuarter = [25.0, 50, 75].contains { (previous < $0) != (newValue < $0) }
                    if newValue == 1 || newValue == 100 || (dragValue != nil && crossesQuarter) { Haptics.edge() }
                    dragValue = newValue
                    onBrightness(newValue)
                }
            }
            .onEnded { _ in
                if dragValue == nil && isPressed {
                    Haptics.tap()
                    if let onOpen { onOpen() } else { onToggle() }
                }
                isPressed = false
                dragValue = nil
            }
    }
}

/// Standard label for slider cards: glowing icon, title, and a subtitle that turns
/// into a live percentage while dragging.
struct CardLabel: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let isOn: Bool
    var glow: Color = .yellow
    var liveValue: Double?

    private var showsPercentage: Bool { liveValue != nil || subtitle.hasSuffix("%") }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 22)
                .opacity(isOn ? 1 : 0.55)
                .shadow(color: isOn ? glow.opacity(0.9) : .clear, radius: 6)
                .symbolEffect(.bounce, value: isOn)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Group {
                    if let liveValue {
                        Text("\(Int(liveValue)) %").monospacedDigit()
                    } else {
                        Text(subtitle)
                    }
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .opacity(0.65)
                .lineLimit(1)
                // Digits morph into digits; between a percentage and a word
                // ("Aus") the label is swapped instead, or the two overlap mid-way.
                .id(showsPercentage)
                .transition(.opacity)
                .contentTransition(.numericText())
            }
        }
    }
}

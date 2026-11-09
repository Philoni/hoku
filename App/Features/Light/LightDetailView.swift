import AppKit
import HueKit
import SwiftUI

struct LightDetailView: View {
    @Environment(HueStore.self) private var store
    let light: Light
    let pop: () -> Void

    enum Mode: String, CaseIterable, Identifiable {
        case color = "Farbe"
        case white = "Weiß"
        var id: Self { self }

        var title: String {
            switch self {
            case .color: String(localized: "Farbe")
            case .white: String(localized: "Weiß")
            }
        }
    }

    @State private var mode: Mode = .color

    var body: some View {
        VStack(spacing: 10) {
            // The name gets the whole row; the lamp shows as its own glowing symbol in the
            // card below, the way rooms do on theirs.
            PageHeader(title: store.name(of: light), subtitle: subtitle, onBack: pop) { EmptyView() }
                .padding(.bottom, 2)

            SliderCard(
                value: light.brightness,
                isOn: light.isOn,
                colors: [light.displayColor],
                height: 54,
                isDimmable: light.supportsDimming,
                onToggle: { store.setOn(!light.isOn, light: light) },
                onBrightness: { store.setBrightness($0, light: light) },
                onAdjust: { [id = light.id] delta in
                    if let light = store.lights[id] { store.adjustBrightness(by: delta, light: light) }
                },
                accessibilityName: String(localized: "Helligkeit"),
                accessibilityState: light.isOn ? "\(Int(light.brightness.rounded())) %" : String(localized: "Aus")
            ) { liveValue in
                CardLabel(
                    systemImage: Icons.light(store.archetype(of: light), dimmable: light.supportsDimming),
                    title: String(localized: "Helligkeit"),
                    subtitle: light.isOn ? "\(Int(light.brightness.rounded())) %" : String(localized: "Aus"),
                    isOn: light.isOn,
                    glow: light.displayColor,
                    liveValue: liveValue
                )
            }

            if light.supportsColor && light.supportsColorTemperature {
                ModePicker(mode: $mode)
            }

            ZStack {
                if mode == .color && light.supportsColor {
                    VStack(spacing: 16) {
                        ColorWheel(light: light)
                            .frame(width: 180, height: 180)
                            .padding(.top, 4)
                        SwatchRow(light: light)
                    }
                    .transition(.blurReplace.combined(with: .scale(0.96)))
                } else if light.supportsColorTemperature {
                    VStack(spacing: 16) {
                        TemperatureSlider(light: light)
                        WhitePresetRow(light: light)
                    }
                    .padding(.top, 4)
                    .transition(.blurReplace.combined(with: .scale(0.96)))
                }
            }
            .animation(Theme.softSpring, value: mode)
        }
        .padding(.bottom, 6)
        .onAppear {
            mode = light.supportsColor && !light.isInColorTemperatureMode ? .color : .white
        }
    }

    /// "Schlafzimmer · Warmweiß 2700 K" – where it is, then what it does.
    private var subtitle: String? {
        let room = light.owner.flatMap { store.devices[$0.rid] }.flatMap { store.room(of: $0) }?.name
        let state: String
        if !light.isOn {
            state = String(localized: "Aus")
        } else if light.isInColorTemperatureMode, let mirek = light.colorTemperature?.mirek {
            state = String(localized: "Weiß · \(Int(ColorMath.kelvin(fromMirek: mirek).rounded())) K")
        } else {
            state = light.supportsColor ? String(localized: "Farbe") : String(localized: "An")
        }
        return [room, state].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Segmented control with a sliding pill.
private struct ModePicker: View {
    @Binding var mode: LightDetailView.Mode
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(LightDetailView.Mode.allCases) { option in
                Button {
                    Haptics.tap()
                    withAnimation(Theme.spring) { mode = option }
                } label: {
                    Text(option.title)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(mode == option ? AnyShapeStyle(Theme.selectedChipText) : AnyShapeStyle(.secondary))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background {
                            if mode == option {
                                Capsule()
                                    .fill(Theme.selectedChip)
                                    .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(mode == option ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.control))
    }
}

/// Hue/saturation wheel with a glowing rim in the light's current color.
struct ColorWheel: View {
    @Environment(HueStore.self) private var store
    let light: Light
    @State private var dragPoint: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let radius = size / 2
            let center = CGPoint(x: radius, y: radius)
            let thumb = dragPoint ?? thumbPosition(radius: radius, center: center)
            let isDragging = dragPoint != nil

            ZStack {
                Circle()
                    .fill(light.displayColor)
                    .blur(radius: 28)
                    .opacity(light.isOn ? 0.55 : 0.15)
                    .scaleEffect(1.05)
                Circle()
                    .fill(AngularGradient(
                        colors: stride(from: 0.0, through: 1.0, by: 1.0 / 12).map {
                            Color(hue: $0, saturation: 1, brightness: 1)
                        },
                        center: .center
                    ))
                Circle()
                    .fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 0, endRadius: radius))
                Circle()
                    .strokeBorder(.white.opacity(0.25), lineWidth: 1)

                Circle()
                    .fill(light.displayColor)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                    .frame(width: 28, height: 28)
                    .scaleEffect(isDragging ? 1.3 : 1)
                    .shadow(color: .black.opacity(0.35), radius: isDragging ? 6 : 3, y: isDragging ? 3 : 1)
                    .position(thumb)
                    .opacity(light.isInColorTemperatureMode && !isDragging ? 0.45 : 1)
                    .animation(Theme.spring, value: isDragging)
                    // Not while dragging: the thumb must stick to the pointer.
                    .animation(isDragging ? nil : Theme.softSpring, value: thumb)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let point = clamp(gesture.location, center: center, radius: radius)
                        dragPoint = point
                        store.setColor(color(at: point, center: center, radius: radius), light: light)
                    }
                    .onEnded { _ in dragPoint = nil }
            )
        }
        .accessibilityElement()
        .accessibilityLabel("Farbrad")
        .accessibilityAdjustableAction { direction in
            shiftHue(by: direction == .increment ? 15 : -15)
        }
    }

    private func shiftHue(by degrees: Double) {
        guard let current = NSColor(light.displayColor).usingColorSpace(.sRGB) else { return }
        var hue = current.hueComponent + degrees / 360
        hue -= hue.rounded(.down)
        let color = NSColor(hue: hue, saturation: max(current.saturationComponent, 0.6), brightness: 1, alpha: 1)
        store.setColor(RGB(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent), light: light)
    }

    private func clamp(_ point: CGPoint, center: CGPoint, radius: CGFloat) -> CGPoint {
        let dx = point.x - center.x, dy = point.y - center.y
        let distance = hypot(dx, dy)
        guard distance > radius else { return point }
        return CGPoint(x: center.x + dx / distance * radius, y: center.y + dy / distance * radius)
    }

    private func color(at point: CGPoint, center: CGPoint, radius: CGFloat) -> RGB {
        let dx = point.x - center.x, dy = point.y - center.y
        // AngularGradient starts at 3 o'clock and runs clockwise (y points down).
        var hue = atan2(dy, dx) / (2 * .pi)
        if hue < 0 { hue += 1 }
        let saturation = min(hypot(dx, dy) / radius, 1)
        let color = NSColor(hue: hue, saturation: saturation, brightness: 1, alpha: 1)
        return RGB(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent)
    }

    private func thumbPosition(radius: CGFloat, center: CGPoint) -> CGPoint {
        guard let resolved = NSColor(light.displayColor).usingColorSpace(.sRGB) else { return center }
        let angle = resolved.hueComponent * 2 * .pi
        let distance = resolved.saturationComponent * radius
        return CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance)
    }
}

struct TemperatureSlider: View {
    @Environment(HueStore.self) private var store
    let light: Light
    @State private var dragMirek: Int?

    var body: some View {
        let schema = light.colorTemperature?.mirekSchema
        let minimum = schema?.mirekMinimum ?? 153
        let maximum = schema?.mirekMaximum ?? 500
        let current = dragMirek ?? light.colorTemperature?.mirek ?? 366
        let stops = stride(from: maximum, through: minimum, by: -max((maximum - minimum) / 8, 1))
            .map { Color(ColorMath.rgb(fromMirek: $0)) }
        let isDragging = dragMirek != nil

        VStack(spacing: 8) {
            GeometryReader { geometry in
                // Warm on the left, cool on the right.
                let fraction = Double(maximum - current) / Double(max(maximum - minimum, 1))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: stops, startPoint: .leading, endPoint: .trailing))
                        .shadow(color: Color(ColorMath.rgb(fromMirek: current)).opacity(0.5), radius: 10)
                    Circle()
                        .fill(Color(ColorMath.rgb(fromMirek: current)))
                        .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                        .frame(width: 30, height: 30)
                        .scaleEffect(isDragging ? 1.2 : 1)
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                        .offset(x: 3 + (geometry.size.width - 36) * min(max(fraction, 0), 1))
                        .opacity(light.isInColorTemperatureMode || isDragging ? 1 : 0.5)
                        .animation(Theme.spring, value: isDragging)
                }
                .contentShape(Capsule())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            let fraction = min(max(gesture.location.x / geometry.size.width, 0), 1)
                            let mirek = maximum - Int((Double(maximum - minimum) * fraction).rounded())
                            if mirek != dragMirek {
                                dragMirek = mirek
                                store.setColorTemperature(mirek: mirek, light: light)
                            }
                        }
                        .onEnded { _ in dragMirek = nil }
                )
            }
            .frame(height: 36)

            HStack {
                Text("Warm")
                Spacer()
                Text("\(Int(ColorMath.kelvin(fromMirek: current).rounded())) K")
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                Spacer()
                Text("Kalt")
            }
            .font(.system(size: 11.5, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .accessibilityElement()
        .accessibilityLabel("Farbtemperatur")
        .accessibilityValue("\(Int(ColorMath.kelvin(fromMirek: current))) Kelvin")
        .accessibilityAdjustableAction { direction in
            // Right is cooler, i.e. fewer mirek.
            let step = direction == .increment ? -20 : 20
            let mirek = min(max(current + step, minimum), maximum)
            guard mirek != current else { return }
            store.setColorTemperature(mirek: mirek, light: light)
        }
    }
}

private struct SwatchRow: View {
    @Environment(HueStore.self) private var store
    let light: Light

    private let swatches: [RGB] = [
        RGB(red: 1, green: 0.12, blue: 0.05),
        RGB(red: 1, green: 0.45, blue: 0),
        RGB(red: 1, green: 0.8, blue: 0.2),
        RGB(red: 0.2, green: 0.9, blue: 0.3),
        RGB(red: 0, green: 0.75, blue: 1),
        RGB(red: 0.2, green: 0.25, blue: 1),
        RGB(red: 0.6, green: 0.2, blue: 1),
        RGB(red: 1, green: 0.2, blue: 0.6),
    ]

    private let swatchNames: [String] = [
        String(localized: "Rot"), String(localized: "Orange"), String(localized: "Gelb"), String(localized: "Grün"),
        String(localized: "Hellblau"), String(localized: "Blau"), String(localized: "Violett"), String(localized: "Pink"),
    ]

    var body: some View {
        let active = activeSwatch
        HStack(spacing: 8) {
            ForEach(Array(swatches.enumerated()), id: \.element) { index, rgb in
                Button {
                    Haptics.tap()
                    store.setColor(rgb, light: light)
                } label: {
                    Circle()
                        .fill(Color(rgb).gradient)
                        .frame(width: 24, height: 24)
                        .shadow(color: Color(rgb).opacity(0.5), radius: 4)
                        .padding(3)
                        .overlay {
                            Circle()
                                .strokeBorder(.primary.opacity(rgb == active ? 0.7 : 0), lineWidth: 1.5)
                        }
                        .scaleEffect(rgb == active ? 1.06 : 1)
                }
                .buttonStyle(PressableStyle())
                .animation(Theme.spring, value: active)
                .accessibilityLabel(swatchNames[index])
                .accessibilityAddTraits(rgb == active ? .isSelected : [])
            }
        }
    }

    /// The swatch closest in hue to the lamp, if it's really that color (in color mode,
    /// saturated, within a few degrees).
    private var activeSwatch: RGB? {
        guard light.isOn, !light.isInColorTemperatureMode,
              let current = NSColor(light.displayColor).usingColorSpace(.sRGB), current.saturationComponent > 0.5
        else { return nil }
        func hueDistance(_ rgb: RGB) -> CGFloat {
            let hue = NSColor(Color(rgb)).usingColorSpace(.sRGB)?.hueComponent ?? 0
            let raw = abs(hue - current.hueComponent)
            return min(raw, 1 - raw)
        }
        guard let nearest = swatches.min(by: { hueDistance($0) < hueDistance($1) }), hueDistance(nearest) < 0.025 else { return nil }
        return nearest
    }
}

private struct WhitePresetRow: View {
    @Environment(HueStore.self) private var store
    let light: Light

    private let presets: [(name: String, kelvin: Int, icon: String)] = [
        (String(localized: "Kerze"), 2200, "flame.fill"),
        (String(localized: "Warm"), 2700, "sun.horizon.fill"),
        (String(localized: "Neutral"), 4000, "sun.min.fill"),
        (String(localized: "Tageslicht"), 6500, "sun.max.fill"),
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(presets, id: \.name) { preset in
                let mirek = ColorMath.mirek(fromKelvin: Double(preset.kelvin))
                let color = Color(ColorMath.rgb(fromMirek: mirek))
                Button {
                    Haptics.tap()
                    store.setColorTemperature(mirek: mirek, light: light)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: preset.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.black.opacity(0.65))
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(color.gradient))
                            .shadow(color: color.opacity(0.6), radius: 6)
                        Text(preset.name)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("\(preset.name), \(preset.kelvin) Kelvin")
            }
        }
    }
}

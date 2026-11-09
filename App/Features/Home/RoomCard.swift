import HueKit
import SwiftUI

struct GroupCard: View {
    @Environment(HueStore.self) private var store
    let group: HueGroup
    var animationDelay: Double = 0
    /// Rooms and lamps that glow out right now ("all off"), see `SliderCard.afterglow`.
    var coolingIDs: Set<String> = []
    /// Shows the room's lamps inline, inside the card.
    var isExpanded = false
    /// Right-click on the card. Rooms with a single lamp only give a little nudge.
    var onExpand: (() -> Void)?
    let open: () -> Void

    @State private var showsAll = false
    @State private var nudge = 0

    var body: some View {
        let groupedLight = store.groupedLight(for: group)
        let isOn = groupedLight?.isOn ?? false
        let colors = store.colors(for: group)
        let lights = store.lights(in: group)
        let isDimmable = lights.contains(where: \.supportsDimming)
        let expanded = isExpanded && lights.count > 1
        // Never "+1 weitere": a single extra row costs the same space as the button.
        let limit = ScreenFit.inlineLamps
        let shown = showsAll || lights.count <= limit + 1 ? lights : Array(lights.prefix(limit))
        let tint = store.tint(for: group)
        // Concentric corners: the tray's 16 pt minus its 5 pt inset.
        let innerRadius = Theme.cardRadius - 5

        VStack(spacing: 5) {
            SliderCard(
                value: groupedLight?.dimming?.brightness ?? 100,
                isOn: isOn,
                colors: colors,
                cornerRadius: expanded ? innerRadius : Theme.cardRadius,
                isDimmable: isDimmable,
                onToggle: { store.setOn(!isOn, group: group) },
                onBrightness: { store.setBrightness($0, group: group) },
                onOpen: open,
                onAdjust: { store.adjustBrightness(by: $0, group: group) },
                animationDelay: animationDelay,
                afterglow: coolingIDs.contains(group.id),
                accessibilityName: group.name,
                accessibilityState: subtitle(isOn: isOn, lights: lights, brightness: groupedLight?.dimming?.brightness, isDimmable: isDimmable)
            ) { liveValue in
                HStack(spacing: 8) {
                    CardLabel(
                        systemImage: Icons.room(group.metadata?.archetype),
                        title: group.name,
                        subtitle: subtitle(isOn: isOn, lights: lights, brightness: groupedLight?.dimming?.brightness, isDimmable: isDimmable),
                        isOn: isOn,
                        glow: colors.first ?? .yellow,
                        liveValue: liveValue
                    )
                    Spacer(minLength: 4)
                    // The orbs step aside once the lamps themselves are listed below.
                    LightOrbs(lights: lights)
                        .opacity(expanded ? 0 : 1)
                        .scaleEffect(expanded ? 0.6 : 1)
                }
            }
            .accessibilityActions {
                if lights.count > 1, let onExpand {
                    Button { onExpand() } label: { Text(isExpanded ? "Lampen einklappen" : "Lampen ausklappen") }
                }
            }

            if expanded {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, light in
                    InlineLightRow(light: light, cornerRadius: innerRadius, animationDelay: animationDelay, afterglow: coolingIDs.contains(light.id))
                        .transition(.cascade(index))
                }
                if shown.count < lights.count {
                    Button {
                        Haptics.tap()
                        withAnimation(Theme.spring) { showsAll = true }
                    } label: {
                        Text("+\(lights.count - shown.count) weitere")
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .transition(.cascade(shown.count))
                }
            }
        }
        .padding(expanded ? 5 : 0)
        .background {
            // Opened, the card becomes a tray glowing in the room's color.
            let tray = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            ZStack {
                tray.fill(Theme.tile)
                if let tint {
                    tray.fill(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.1)], startPoint: .top, endPoint: .bottom))
                }
                tray.strokeBorder(Theme.tileStroke, lineWidth: 1)
            }
            .opacity(expanded ? 1 : 0)
        }
        .keyframeAnimator(initialValue: 1.0, trigger: nudge) { view, scale in
            view.scaleEffect(scale)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(1.02, duration: 0.1)
                SpringKeyframe(1.0, duration: 0.3, spring: .bouncy)
            }
        }
        .onSecondaryClick {
            guard let onExpand else { return }
            if lights.count > 1 {
                Haptics.tap()
                onExpand()
            } else {
                nudge += 1
            }
        }
        .onChange(of: isExpanded) {
            if !isExpanded { showsAll = false }
        }
    }

    /// As little text as possible: the scene, else the brightness; counts only when mixed.
    private func subtitle(isOn: Bool, lights: [Light], brightness: Double?, isDimmable: Bool) -> String {
        if let fadeOut = store.fadeOuts[group.id] {
            return String(localized: "Dimmt aus bis \(fadeOut.ends.formatted(date: .omitted, time: .shortened))")
        }
        guard isOn else { return lights.isEmpty ? String(localized: "Keine Lampen") : String(localized: "Aus") }
        if let scene = store.activeScene(in: group) { return scene.name }
        let onCount = lights.filter(\.isOn).count
        if onCount < lights.count { return String(localized: "\(onCount) von \(lights.count) an") }
        guard isDimmable, let brightness else { return String(localized: "An") }
        return "\(Int(brightness.rounded())) %"
    }
}

/// A lamp inside an expanded room card: switch it, or drag to dim.
private struct InlineLightRow: View {
    @Environment(HueStore.self) private var store
    let light: Light
    let cornerRadius: CGFloat
    var animationDelay: Double = 0
    var afterglow = false

    var body: some View {
        SliderCard(
            value: light.brightness,
            isOn: light.isOn,
            colors: [light.displayColor],
            height: 34,
            cornerRadius: cornerRadius,
            isCompact: true,
            isDimmable: light.supportsDimming,
            onToggle: { store.setOn(!light.isOn, light: light) },
            onBrightness: { store.setBrightness($0, light: light) },
            onAdjust: { [id = light.id] delta in
                if let light = store.lights[id] { store.adjustBrightness(by: delta, light: light) }
            },
            animationDelay: animationDelay,
            afterglow: afterglow,
            accessibilityName: store.name(of: light),
            accessibilityState: state
        ) { liveValue in
            HStack(spacing: 8) {
                Circle()
                    .fill(light.isOn ? light.displayColor : .clear)
                    .overlay(Circle().strokeBorder(light.isOn ? AnyShapeStyle(.white.opacity(0.6)) : AnyShapeStyle(Theme.faint), lineWidth: 1))
                    .frame(width: 8, height: 8)
                    .shadow(color: light.isOn ? light.displayColor : .clear, radius: 3)
                Text(store.name(of: light))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Group {
                    if let liveValue {
                        Text("\(Int(liveValue)) %")
                    } else {
                        Text(state)
                    }
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .opacity(0.7)
                .contentTransition(.numericText())
            }
        }
    }

    private var state: String {
        guard store.isReachable(light) else { return String(localized: "Nicht erreichbar") }
        guard light.isOn else { return String(localized: "Aus") }
        return light.supportsDimming ? "\(Int(light.brightness.rounded())) %" : String(localized: "An")
    }
}

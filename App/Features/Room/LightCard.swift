import HueKit
import SwiftUI

struct LightCard: View {
    @Environment(HueStore.self) private var store
    let light: Light
    /// Scene preview: how this light would look; shown instead of the real state.
    var preview: LightPreview?
    let open: () -> Void

    var body: some View {
        let hasDetail = light.supportsColor || light.supportsColorTemperature

        SliderCard(
            value: preview?.brightness ?? light.brightness,
            isOn: preview?.isOn ?? light.isOn,
            colors: [preview?.color ?? light.displayColor],
            height: 48,
            isDimmable: light.supportsDimming,
            onToggle: { store.setOn(!light.isOn, light: light) },
            onBrightness: { store.setBrightness($0, light: light) },
            onOpen: hasDetail ? open : nil,
            onAdjust: { [id = light.id] delta in
                if let light = store.lights[id] { store.adjustBrightness(by: delta, light: light) }
            }
        ) { liveValue in
            CardLabel(
                systemImage: Icons.light(store.archetype(of: light), dimmable: light.supportsDimming),
                title: store.name(of: light),
                subtitle: preview.map { $0.isOn ? (light.supportsDimming ? "→ \(Int($0.brightness.rounded())) %" : "→ An") : "→ Aus" } ?? subtitle,
                isOn: preview?.isOn ?? light.isOn,
                glow: preview?.color ?? light.displayColor,
                liveValue: liveValue
            )
        }
    }

    private var subtitle: String {
        if !store.isReachable(light) { return "Nicht erreichbar" }
        if light.isStreaming { return "Sync aktiv" }
        guard light.isOn else { return "Aus" }
        guard light.supportsDimming else { return "An" }
        return "\(Int(light.brightness.rounded())) %"
    }
}

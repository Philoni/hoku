import HueKit
import SwiftUI

/// One glowing dot per light, in its real color; brighter lights glow wider.
struct LightOrbs: View {
    @Environment(HueStore.self) private var store
    let lights: [Light]
    var limit = 6

    var body: some View {
        HStack(spacing: 4) {
            ForEach(lights.prefix(limit)) { light in
                let level = light.isOn ? (light.supportsDimming ? light.brightness / 100 : 0.8) : 0
                Circle()
                    .fill(light.isOn ? light.displayColor : .clear)
                    .overlay(Circle().strokeBorder(light.isOn ? AnyShapeStyle(.white.opacity(0.55)) : AnyShapeStyle(Theme.faint), lineWidth: 1))
                    .frame(width: 7, height: 7)
                    .shadow(color: light.displayColor.opacity(light.isOn ? 0.5 + 0.5 * level : 0), radius: 1.5 + 4 * level)
                    .help(store.name(of: light))
            }
            if lights.count > limit {
                Text("+\(lights.count - limit)")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .opacity(0.6)
            }
        }
        .animation(Theme.spring, value: lights.map(\.isOn))
        .accessibilityHidden(true)
    }
}

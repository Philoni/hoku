import HueKit
import SwiftUI

extension Color {
    init(_ rgb: RGB) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

extension Light {
    /// What the light looks like right now, for tinting UI.
    var displayColor: Color {
        if isInColorTemperatureMode, let mirek = colorTemperature?.mirek {
            return Color(ColorMath.rgb(fromMirek: mirek))
        }
        if let xy = color?.xy {
            return Color(ColorMath.rgb(from: xy))
        }
        if let mirek = colorTemperature?.mirek {
            return Color(ColorMath.rgb(fromMirek: mirek))
        }
        // Plain white lights and plugs: a warm white.
        return Color(ColorMath.rgb(fromMirek: 370))
    }
}

extension HueScene {
    /// Up to five representative colors for a scene tile.
    var displayColors: [Color] {
        var colors: [Color] = []
        for entry in palette?.color ?? [] {
            colors.append(Color(ColorMath.rgb(from: entry.color.xy)))
        }
        for entry in palette?.colorTemperature ?? [] {
            if let mirek = entry.colorTemperature.mirek {
                colors.append(Color(ColorMath.rgb(fromMirek: mirek)))
            }
        }
        if colors.isEmpty {
            for action in actions ?? [] {
                if let points = action.action.gradient?.points, !points.isEmpty {
                    colors += points.map { Color(ColorMath.rgb(from: $0.color.xy)) }
                } else if let xy = action.action.color?.xy {
                    colors.append(Color(ColorMath.rgb(from: xy)))
                } else if let mirek = action.action.colorTemperature?.mirek {
                    colors.append(Color(ColorMath.rgb(fromMirek: mirek)))
                }
            }
        }
        if colors.isEmpty { colors = [Color(ColorMath.rgb(fromMirek: 370))] }
        return Array(colors.prefix(5))
    }
}

extension HueStore {
    /// Colors of the lights that are on in a group, in a stable order, for card fills.
    func colors(for group: HueGroup) -> [Color] {
        lights(in: group).filter(\.isOn).map(\.displayColor)
    }

    /// Colors of every light that is on, for the ambient background.
    var colorsOfLightsOn: [Color] {
        lights.values
            .filter(\.isOn)
            .sorted { $0.id < $1.id }
            .map(\.displayColor)
    }

    /// Average color of the lights that are on in a group, for card tints.
    func tint(for group: HueGroup) -> Color? {
        let on = lights(in: group).filter(\.isOn)
        guard !on.isEmpty else { return nil }
        let resolved = on.map { NSColor($0.displayColor).usingColorSpace(.sRGB) ?? .white }
        let count = CGFloat(resolved.count)
        return Color(
            red: resolved.map(\.redComponent).reduce(0, +) / count,
            green: resolved.map(\.greenComponent).reduce(0, +) / count,
            blue: resolved.map(\.blueComponent).reduce(0, +) / count
        )
    }
}

extension HueStore.ConnectionState {
    var title: String {
        switch self {
        case .live: String(localized: "Live verbunden")
        case .connecting: String(localized: "Verbinde …")
        case .disconnected: String(localized: "Getrennt")
        case let .offline(reason): String(localized: "Offline (\(reason))")
        case .unauthorized: String(localized: "Nicht autorisiert")
        }
    }
}

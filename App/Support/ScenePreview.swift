import HueKit
import SwiftUI

/// How a light would look in a scene, for hover previews.
struct LightPreview: Equatable {
    var isOn: Bool
    var brightness: Double
    var color: Color
}

extension HueScene {
    func preview(for light: Light) -> LightPreview? {
        guard let action = actions?.first(where: { $0.target.rid == light.id })?.action else { return nil }
        let color: Color
        if let point = action.gradient?.points?.first {
            color = Color(ColorMath.rgb(from: point.color.xy))
        } else if let xy = action.color?.xy {
            color = Color(ColorMath.rgb(from: xy))
        } else if let mirek = action.colorTemperature?.mirek {
            color = Color(ColorMath.rgb(fromMirek: mirek))
        } else {
            color = light.displayColor
        }
        return LightPreview(
            isOn: action.on?.on ?? true,
            brightness: action.dimming?.brightness ?? (light.supportsDimming ? 100 : 100),
            color: color
        )
    }
}

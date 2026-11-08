import Foundation

/// SF Symbols for Hue archetypes.
enum Icons {
    static func room(_ archetype: String?) -> String {
        switch archetype {
        case "living_room", "lounge", "tv", "man_cave": "sofa.fill"
        case "bedroom", "kids_bedroom", "guest_room": "bed.double.fill"
        case "kitchen": "refrigerator.fill"
        case "dining": "fork.knife"
        case "bathroom", "toilet": "shower.fill"
        case "office", "computer", "studio": "desktopcomputer"
        case "hallway", "staircase", "top_floor", "upstairs", "downstairs", "front_door": "door.left.hand.open"
        case "garden", "terrace", "balcony", "porch", "driveway", "carport", "pool": "leaf.fill"
        case "garage": "car.fill"
        case "gym": "dumbbell.fill"
        case "nursery": "teddybear.fill"
        case "reading": "book.fill"
        case "home": "house.fill"
        default: "square.grid.2x2.fill"
        }
    }

    static func light(_ archetype: String?, dimmable: Bool) -> String {
        switch archetype {
        case "hue_lightstrip", "hue_lightstrip_tv", "hue_lightstrip_pc", "hue_play_gradient_lightstrip": "light.strip.2"
        case "floor_shade", "floor_lantern", "hue_signe", "hue_gradient_signe": "lamp.floor.fill"
        case "table_shade", "table_wash", "hue_go", "hue_iris", "flexible_lamp": "lamp.table.fill"
        case "ceiling_round", "ceiling_square", "ceiling_tube", "ceiling_horizontal", "pendant_round", "pendant_long", "pendant_spot", "hue_centris", "hue_tube": "lamp.ceiling.fill"
        case "chandelier", "christmas_tree": "chandelier.fill"
        case "recessed_ceiling", "recessed_floor", "spot_bulb", "single_spot", "double_spot": "light.recessed.fill"
        case "plug": "powerplug.fill"
        case "desk_lamp": "lamp.desk.fill"
        case "hue_play", "hue_bloom", "wall_shade", "wall_spot", "wall_lantern": "lightspectrum.horizontal"
        default: dimmable ? "lightbulb.fill" : "powerplug.fill"
        }
    }
}

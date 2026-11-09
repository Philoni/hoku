import Foundation

// Typed views of CLIP v2 resources. Everything beyond `id` is optional on purpose:
// the bridge adds fields and enum values over time, and decoding must never fail
// because of something we don't use.

public struct ResourceIdentifier: Codable, Hashable, Sendable {
    public var rid: String
    public var rtype: String

    public init(rid: String, rtype: String) {
        self.rid = rid
        self.rtype = rtype
    }
}

public struct XY: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct Gamut: Codable, Hashable, Sendable {
    public var red: XY
    public var green: XY
    public var blue: XY
}

public struct Metadata: Codable, Hashable, Sendable {
    public var name: String?
    public var archetype: String?
}

public struct OnState: Codable, Hashable, Sendable {
    public var on: Bool
}

public struct Dimming: Codable, Hashable, Sendable {
    public var brightness: Double
    public var minDimLevel: Double?

    enum CodingKeys: String, CodingKey {
        case brightness
        case minDimLevel = "min_dim_level"
    }
}

public struct MirekSchema: Codable, Hashable, Sendable {
    public var mirekMinimum: Int
    public var mirekMaximum: Int

    enum CodingKeys: String, CodingKey {
        case mirekMinimum = "mirek_minimum"
        case mirekMaximum = "mirek_maximum"
    }
}

public struct ColorTemperature: Codable, Hashable, Sendable {
    public var mirek: Int?
    public var mirekValid: Bool?
    public var mirekSchema: MirekSchema?

    enum CodingKeys: String, CodingKey {
        case mirek
        case mirekValid = "mirek_valid"
        case mirekSchema = "mirek_schema"
    }
}

public struct LightColor: Codable, Hashable, Sendable {
    public var xy: XY
    public var gamut: Gamut?
    public var gamutType: String?

    enum CodingKeys: String, CodingKey {
        case xy, gamut
        case gamutType = "gamut_type"
    }
}

public struct GradientPoint: Codable, Hashable, Sendable {
    public struct PointColor: Codable, Hashable, Sendable {
        public var xy: XY
    }

    public var color: PointColor
}

public struct HueGradient: Codable, Hashable, Sendable {
    public var points: [GradientPoint]?
    public var pointsCapable: Int?
    public var mode: String?

    enum CodingKeys: String, CodingKey {
        case points, mode
        case pointsCapable = "points_capable"
    }
}

public struct LightDynamics: Codable, Hashable, Sendable {
    public var status: String?
    public var speed: Double?
    public var speedValid: Bool?

    enum CodingKeys: String, CodingKey {
        case status, speed
        case speedValid = "speed_valid"
    }
}

public struct EffectsV2: Codable, Hashable, Sendable {
    public struct Status: Codable, Hashable, Sendable {
        public var effect: String?
        public var effectValues: [String]?

        enum CodingKeys: String, CodingKey {
            case effect
            case effectValues = "effect_values"
        }
    }

    public struct Action: Codable, Hashable, Sendable {
        public var effectValues: [String]?

        enum CodingKeys: String, CodingKey {
            case effectValues = "effect_values"
        }
    }

    public var status: Status?
    public var action: Action?
}

// MARK: - Resources

public struct Light: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var owner: ResourceIdentifier?
    public var metadata: Metadata?
    public var on: OnState?
    public var dimming: Dimming?
    public var colorTemperature: ColorTemperature?
    public var color: LightColor?
    public var gradient: HueGradient?
    public var dynamics: LightDynamics?
    public var effectsV2: EffectsV2?
    /// "normal" or "streaming" (owned by an entertainment/sync app).
    public var mode: String?

    enum CodingKeys: String, CodingKey {
        case id, owner, metadata, on, dimming, color, gradient, dynamics, mode
        case colorTemperature = "color_temperature"
        case effectsV2 = "effects_v2"
    }

    public var isOn: Bool { on?.on ?? false }
    public var brightness: Double { dimming?.brightness ?? 100 }
    public var supportsDimming: Bool { dimming != nil }
    public var supportsColor: Bool { color != nil }
    public var supportsColorTemperature: Bool { colorTemperature != nil }
    public var isStreaming: Bool { mode == "streaming" }

    /// The light is currently showing a color temperature rather than an xy color.
    public var isInColorTemperatureMode: Bool {
        colorTemperature?.mirekValid == true && colorTemperature?.mirek != nil
    }
}

public struct GroupedLight: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var owner: ResourceIdentifier?
    public var on: OnState?
    public var dimming: Dimming?

    public var isOn: Bool { on?.on ?? false }
}

/// A room or a zone. Rooms list devices as children, zones list light services.
public struct HueGroup: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var type: String
    public var metadata: Metadata?
    public var children: [ResourceIdentifier]?
    public var services: [ResourceIdentifier]?

    public var name: String { metadata?.name ?? String(localized: "Unbenannt", bundle: .hueKit) }
    public var isZone: Bool { type == "zone" }

    public var groupedLightID: String? {
        services?.first { $0.rtype == "grouped_light" }?.rid
    }
}

public struct Device: Codable, Hashable, Sendable, Identifiable {
    public struct ProductData: Codable, Hashable, Sendable {
        public var modelID: String?
        public var productName: String?
        public var productArchetype: String?

        enum CodingKeys: String, CodingKey {
            case modelID = "model_id"
            case productName = "product_name"
            case productArchetype = "product_archetype"
        }
    }

    public var id: String
    public var metadata: Metadata?
    public var productData: ProductData?
    public var services: [ResourceIdentifier]?

    enum CodingKeys: String, CodingKey {
        case id, metadata, services
        case productData = "product_data"
    }

    public var lightIDs: [String] {
        services?.filter { $0.rtype == "light" }.map(\.rid) ?? []
    }
}

public struct HueScene: Codable, Hashable, Sendable, Identifiable {
    public struct SceneAction: Codable, Hashable, Sendable {
        public struct Action: Codable, Hashable, Sendable {
            public var on: OnState?
            public var dimming: Dimming?
            public var color: SceneColor?
            public var colorTemperature: SceneColorTemperature?
            public var gradient: HueGradient?

            enum CodingKeys: String, CodingKey {
                case on, dimming, color, gradient
                case colorTemperature = "color_temperature"
            }
        }

        public var target: ResourceIdentifier
        public var action: Action
    }

    public struct SceneColor: Codable, Hashable, Sendable {
        public var xy: XY
    }

    public struct SceneColorTemperature: Codable, Hashable, Sendable {
        public var mirek: Int?
    }

    public struct Palette: Codable, Hashable, Sendable {
        public struct ColorEntry: Codable, Hashable, Sendable {
            public var color: SceneColor
            public var dimming: Dimming?
        }

        public struct TemperatureEntry: Codable, Hashable, Sendable {
            public var colorTemperature: SceneColorTemperature
            public var dimming: Dimming?

            enum CodingKeys: String, CodingKey {
                case dimming
                case colorTemperature = "color_temperature"
            }
        }

        public var color: [ColorEntry]?
        public var colorTemperature: [TemperatureEntry]?

        enum CodingKeys: String, CodingKey {
            case color
            case colorTemperature = "color_temperature"
        }
    }

    public struct Status: Codable, Hashable, Sendable {
        /// "inactive", "static" or "dynamic_palette".
        public var active: String?
    }

    public var id: String
    public var metadata: Metadata?
    public var group: ResourceIdentifier?
    public var actions: [SceneAction]?
    public var palette: Palette?
    public var speed: Double?
    public var autoDynamic: Bool?
    public var status: Status?

    enum CodingKeys: String, CodingKey {
        case id, metadata, group, actions, palette, speed, status
        case autoDynamic = "auto_dynamic"
    }

    public var name: String { metadata?.name ?? String(localized: "Szene", bundle: .hueKit) }

    /// The scene has a palette the bridge can cycle through.
    public var supportsDynamic: Bool {
        !(palette?.color ?? []).isEmpty || (palette?.colorTemperature ?? []).count > 1
    }

    public var isActive: Bool {
        guard let active = status?.active else { return false }
        return active != "inactive"
    }

    public var isPlayingDynamically: Bool { status?.active == "dynamic_palette" }
}

public struct SmartScene: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var metadata: Metadata?
    public var group: ResourceIdentifier?
    /// "active" or "inactive".
    public var state: String?

    public var name: String { metadata?.name ?? String(localized: "Smarte Szene", bundle: .hueKit) }
    public var isActive: Bool { state == "active" }
}

public struct BridgeHome: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var children: [ResourceIdentifier]?
    public var services: [ResourceIdentifier]?

    public var groupedLightID: String? {
        services?.first { $0.rtype == "grouped_light" }?.rid
    }
}

public struct BridgeResource: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var bridgeID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case bridgeID = "bridge_id"
    }
}

// MARK: - Automations (behaviors)

public struct BehaviorScript: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var metadata: Metadata?
    public var description: String?

    public var name: String { metadata?.name ?? "" }
}

/// An automation instance as created by the Hue app (wake-up, go-to-sleep, timers …).
/// Only the parts Hoku shows are typed; edits patch the raw JSON so unknown
/// configuration fields survive.
public struct BehaviorInstance: Codable, Hashable, Sendable, Identifiable {
    public struct Configuration: Codable, Hashable, Sendable {
        public struct When: Codable, Hashable, Sendable {
            public struct TimePoint: Codable, Hashable, Sendable {
                public struct Time: Codable, Hashable, Sendable {
                    public var hour: Int
                    public var minute: Int
                }

                public var type: String?
                public var time: Time?
            }

            public var recurrenceDays: [String]?
            public var timePoint: TimePoint?

            enum CodingKeys: String, CodingKey {
                case recurrenceDays = "recurrence_days"
                case timePoint = "time_point"
            }
        }

        public struct Duration: Codable, Hashable, Sendable {
            public var seconds: Int
        }

        public struct Where: Codable, Hashable, Sendable {
            public var group: ResourceIdentifier?
            public var items: [ResourceIdentifier]?
        }

        public var when: When?
        public var `where`: [Where]?
        public var style: String?
        public var endBrightness: Double?
        public var endState: String?
        public var fadeInDuration: Duration?
        public var fadeOutDuration: Duration?

        enum CodingKeys: String, CodingKey {
            case when, `where`, style
            case endBrightness = "end_brightness"
            case endState = "end_state"
            case fadeInDuration = "fade_in_duration"
            case fadeOutDuration = "fade_out_duration"
        }
    }

    public var id: String
    public var scriptID: String
    public var enabled: Bool
    public var metadata: Metadata?
    public var configuration: Configuration?

    enum CodingKeys: String, CodingKey {
        case id, enabled, metadata, configuration
        case scriptID = "script_id"
    }

    public var name: String { metadata?.name ?? String(localized: "Automation", bundle: .hueKit) }
    public var hour: Int? { configuration?.when?.timePoint?.time?.hour }
    public var minute: Int? { configuration?.when?.timePoint?.time?.minute }
    public var weekdays: [String] { configuration?.when?.recurrenceDays ?? [] }
    public var groupIDs: [String] { configuration?.where?.compactMap { $0.group?.rid } ?? [] }

    /// Fade length in seconds (fade-in for wake-ups, fade-out for go-to-sleep).
    public var fadeSeconds: Int? {
        configuration?.fadeInDuration?.seconds ?? configuration?.fadeOutDuration?.seconds
    }
}

// MARK: - Device health

public struct DevicePower: Codable, Hashable, Sendable, Identifiable {
    public struct PowerState: Codable, Hashable, Sendable {
        /// "normal", "low" or "critical".
        public var batteryState: String?
        public var batteryLevel: Int?

        enum CodingKeys: String, CodingKey {
            case batteryState = "battery_state"
            case batteryLevel = "battery_level"
        }
    }

    public var id: String
    public var owner: ResourceIdentifier?
    public var powerState: PowerState?

    enum CodingKeys: String, CodingKey {
        case id, owner
        case powerState = "power_state"
    }
}

public struct ZigbeeConnectivity: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var owner: ResourceIdentifier?
    /// "connected", "disconnected", "connectivity_issue" or "unidirectional_incoming".
    public var status: String?

    public var isConnected: Bool { status == nil || status == "connected" }
}

public struct DeviceSoftwareUpdate: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var owner: ResourceIdentifier?
    /// "no_update", "update_pending", "ready_to_install", "installing" …
    public var state: String?

    public var hasUpdate: Bool { state != nil && state != "no_update" }
}

/// An entertainment area. While it is active, a sync app (Hue Sync, a sync box, a game)
/// streams to its lights many times a second and overrides what anyone else sends them.
public struct EntertainmentArea: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var metadata: Metadata?
    public var status: String?

    public init(id: String, name: String, status: String) {
        self.id = id
        self.metadata = Metadata(name: name)
        self.status = status
    }

    public var name: String { metadata?.name ?? String(localized: "Entertainment-Bereich", bundle: .hueKit) }
    public var isStreaming: Bool { status == "active" }
}

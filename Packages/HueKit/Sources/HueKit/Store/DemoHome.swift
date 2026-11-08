import Foundation

/// A made-up home for screenshots, previews and the README – no real bridge, no
/// personal data. `HOKU_DEMO=1` together with `HOKU_SNAPSHOT=<dir>` renders it.
public enum DemoHome {
    private struct Lamp {
        var name: String
        var archetype: String
        var isOn: Bool
        var brightness: Double = 100
        /// CIE xy for color lamps; nil for white-only lamps.
        var xy: (Double, Double)?
        /// Color temperature in mirek when in white mode.
        var mirek: Int?
        var isPlug = false
    }

    private struct Scene {
        var name: String
        var colors: [(Double, Double)] = []
        var mirek: Int?
        var isActive = false
        var isDynamic = false
    }

    private struct Room {
        var name: String
        var archetype: String
        var lamps: [Lamp]
        var scenes: [Scene]
    }

    private static let rooms: [Room] = [
        Room(name: "Wohnzimmer", archetype: "living_room", lamps: [
            Lamp(name: "Stehlampe", archetype: "floor_shade", isOn: true, brightness: 72, xy: (0.556, 0.398)),
            Lamp(name: "Sofa-Lightstrip", archetype: "hue_lightstrip", isOn: true, brightness: 58, xy: (0.598, 0.352)),
            Lamp(name: "Leselampe", archetype: "table_shade", isOn: true, brightness: 64, xy: (0.501, 0.415)),
        ], scenes: [
            Scene(name: "Sonnenuntergang", colors: [(0.62, 0.36), (0.56, 0.40), (0.47, 0.28)], isActive: true, isDynamic: true),
            Scene(name: "Entspannen", mirek: 447),
            Scene(name: "Tropendämmerung", colors: [(0.56, 0.38), (0.45, 0.21), (0.27, 0.14)], isDynamic: true),
            Scene(name: "Lesen", mirek: 346),
            Scene(name: "Konzentrieren", mirek: 233),
            Scene(name: "Nachtlicht", colors: [(0.56, 0.40)]),
        ]),
        Room(name: "Küche", archetype: "kitchen", lamps: [
            Lamp(name: "Deckenspots", archetype: "spot_bulb", isOn: false, mirek: 300),
            Lamp(name: "Arbeitsplatte", archetype: "hue_lightstrip", isOn: false, xy: (0.46, 0.41)),
        ], scenes: [
            Scene(name: "Hell", mirek: 300),
            Scene(name: "Gemütlich", mirek: 454),
        ]),
        Room(name: "Schlafzimmer", archetype: "bedroom", lamps: [
            Lamp(name: "Nachttisch links", archetype: "table_shade", isOn: true, brightness: 26, xy: (0.42, 0.24)),
            Lamp(name: "Nachttisch rechts", archetype: "table_shade", isOn: true, brightness: 26, xy: (0.33, 0.17)),
            Lamp(name: "Deckenlampe", archetype: "ceiling_round", isOn: false, mirek: 366),
        ], scenes: [
            Scene(name: "Arktische Aurora", colors: [(0.17, 0.30), (0.25, 0.13), (0.33, 0.17)], isActive: true, isDynamic: true),
            Scene(name: "Nachtlicht", colors: [(0.56, 0.40)]),
            Scene(name: "Entspannen", mirek: 447),
        ]),
        Room(name: "Büro", archetype: "office", lamps: [
            Lamp(name: "Schreibtisch", archetype: "table_wash", isOn: true, brightness: 88, mirek: 250),
            Lamp(name: "Play-Bars", archetype: "hue_play", isOn: true, brightness: 60, xy: (0.17, 0.12)),
            Lamp(name: "Regal", archetype: "classic_bulb", isOn: false, mirek: 370, isPlug: false),
        ], scenes: [
            Scene(name: "Konzentrieren", mirek: 233, isActive: true),
            Scene(name: "Energie tanken", mirek: 181),
            Scene(name: "Gaming", colors: [(0.17, 0.12), (0.30, 0.14), (0.16, 0.33)], isDynamic: true),
        ]),
        Room(name: "Flur", archetype: "hallway", lamps: [
            Lamp(name: "Flurlicht", archetype: "ceiling_round", isOn: false, mirek: 370),
        ], scenes: [
            Scene(name: "Hell", mirek: 300),
        ]),
    ]

    public static let credentials = BridgeCredentials(
        bridgeID: "001788fffe00demo", host: "192.168.1.20", applicationKey: "demo", name: "Hue Bridge · Demo"
    )

    public static func resources() -> [JSONValue] {
        var resources: [JSONValue] = []
        var roomIDs: [String] = []

        for (r, room) in rooms.enumerated() {
            let roomID = "demo-room-\(r)"
            let groupedID = "demo-grouped-\(r)"
            roomIDs.append(roomID)
            var children: [JSONValue] = []
            var lightIDs: [String] = []
            for (l, lamp) in room.lamps.enumerated() {
                let deviceID = "demo-device-\(r)-\(l)"
                let lightID = "demo-light-\(r)-\(l)"
                lightIDs.append(lightID)
                children.append(["rid": .string(deviceID), "rtype": "device"])
                resources.append([
                    "id": .string(deviceID), "type": "device",
                    "metadata": ["name": .string(lamp.name), "archetype": .string(lamp.archetype)],
                    "product_data": ["product_name": "Hue", "product_archetype": .string(lamp.archetype), "software_version": "1.122.2"],
                    "services": [
                        ["rid": .string(lightID), "rtype": "light"],
                        ["rid": .string("demo-zigbee-\(r)-\(l)"), "rtype": "zigbee_connectivity"],
                    ],
                ])
                resources.append([
                    "id": .string("demo-zigbee-\(r)-\(l)"), "type": "zigbee_connectivity",
                    "owner": ["rid": .string(deviceID), "rtype": "device"], "status": "connected",
                ])
                resources.append(light(lamp, id: lightID, deviceID: deviceID))
            }
            let anyOn = room.lamps.contains(where: \.isOn)
            let onBrightness = room.lamps.filter(\.isOn).map(\.brightness)
            resources.append([
                "id": .string(roomID), "type": "room",
                "metadata": ["name": .string(room.name), "archetype": .string(room.archetype)],
                "children": .array(children),
                "services": [["rid": .string(groupedID), "rtype": "grouped_light"]],
            ])
            resources.append([
                "id": .string(groupedID), "type": "grouped_light",
                "owner": ["rid": .string(roomID), "rtype": "room"],
                "on": ["on": .bool(anyOn)],
                "dimming": ["brightness": .number(onBrightness.isEmpty ? 0 : onBrightness.reduce(0, +) / Double(onBrightness.count))],
            ])
            for (s, scene) in room.scenes.enumerated() {
                resources.append(sceneResource(scene, id: "demo-scene-\(r)-\(s)", roomID: roomID, lightIDs: lightIDs))
            }
        }

        resources.append([
            "id": "demo-home", "type": "bridge_home",
            "children": .array(roomIDs.map { ["rid": .string($0), "rtype": "room"] }),
            "services": [["rid": "demo-home-grouped", "rtype": "grouped_light"]],
        ])
        resources.append([
            "id": "demo-home-grouped", "type": "grouped_light",
            "owner": ["rid": "demo-home", "rtype": "bridge_home"], "on": ["on": true],
        ])
        resources.append(["id": "demo-homekit", "type": "homekit", "status": "unpaired"])
        return resources
    }

    private static func light(_ lamp: Lamp, id: String, deviceID: String) -> JSONValue {
        var value: JSONValue = [
            "id": .string(id), "type": "light",
            "owner": ["rid": .string(deviceID), "rtype": "device"],
            "metadata": ["name": .string(lamp.name), "archetype": .string(lamp.archetype)],
            "on": ["on": .bool(lamp.isOn)],
            "mode": "normal",
        ]
        guard !lamp.isPlug else { return value }
        value = value.merging([
            "dimming": ["brightness": .number(lamp.brightness), "min_dim_level": 0.2],
            "color_temperature": [
                "mirek": lamp.mirek.map { .number(Double($0)) } ?? .null,
                "mirek_valid": .bool(lamp.mirek != nil),
                "mirek_schema": ["mirek_minimum": 153, "mirek_maximum": 500],
            ],
        ])
        if let xy = lamp.xy {
            value = value.merging([
                "color": [
                    "xy": ["x": .number(xy.0), "y": .number(xy.1)],
                    "gamut_type": "C",
                    "gamut": ["red": ["x": 0.6915, "y": 0.3083], "green": ["x": 0.17, "y": 0.7], "blue": ["x": 0.1532, "y": 0.0475]],
                ],
            ])
        }
        return value
    }

    private static func sceneResource(_ scene: Scene, id: String, roomID: String, lightIDs: [String]) -> JSONValue {
        let palette: JSONValue = [
            "color": .array(scene.colors.map { ["color": ["xy": ["x": .number($0.0), "y": .number($0.1)]], "dimming": ["brightness": 70]] }),
            "color_temperature": .array(scene.mirek.map { [["color_temperature": ["mirek": .number(Double($0))], "dimming": ["brightness": 80]]] } ?? []),
            "dimming": [], "effects": [], "effects_v2": [],
        ]
        let actions: [JSONValue] = lightIDs.enumerated().map { index, lightID in
            var action: JSONValue = ["on": ["on": true], "dimming": ["brightness": 70]]
            if !scene.colors.isEmpty {
                let xy = scene.colors[index % scene.colors.count]
                action = action.merging(["color": ["xy": ["x": .number(xy.0), "y": .number(xy.1)]]])
            } else if let mirek = scene.mirek {
                action = action.merging(["color_temperature": ["mirek": .number(Double(mirek))]])
            }
            return ["target": ["rid": .string(lightID), "rtype": "light"], "action": action]
        }
        return [
            "id": .string(id), "type": "scene",
            "metadata": ["name": .string(scene.name)],
            "group": ["rid": .string(roomID), "rtype": "room"],
            "actions": .array(actions),
            "palette": palette,
            "speed": 0.5,
            "auto_dynamic": .bool(scene.isDynamic),
            "status": ["active": .string(scene.isActive ? (scene.isDynamic ? "dynamic_palette" : "static") : "inactive")],
        ]
    }
}

extension HueStore {
    /// Shows the demo home instead of a real bridge (no network at all).
    public func showDemo() {
        disconnect()
        credentials = DemoHome.credentials
        load(DemoHome.resources())
        connection = .live
    }
}

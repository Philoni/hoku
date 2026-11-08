import AppIntents
import HueKit

// Actions for Siri, Shortcuts and Spotlight. They are stateless and talk to the bridge
// directly (HueRemote); the app notices the change through its event stream.

struct SetRoomPowerIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Raum schalten"
    static let description = IntentDescription("Schaltet alle Lampen in einem Raum oder einer Zone an oder aus.")

    @Parameter(title: "Raum")
    var room: RoomEntity?

    @Parameter(title: "An")
    var value: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Schalte \(\.$room) \(\.$value)")
    }

    init() {}

    init(room: RoomEntity?) {
        self.room = room
    }

    init(on: Bool) {
        value = on
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let room else { throw $room.needsValueError("Welchen Raum?") }
        try await HueRemote.shared.setOn(value, groupedLight: room.groupedLightID)
        return .result(dialog: "\(room.name) ist \(value ? "an" : "aus").")
    }
}

struct SetRoomBrightnessIntent: AppIntent {
    static let title: LocalizedStringResource = "Raum dimmen"
    static let description = IntentDescription("Stellt die Helligkeit eines Raums ein und schaltet ihn dabei an.")

    @Parameter(title: "Raum")
    var room: RoomEntity

    @Parameter(title: "Helligkeit", inclusiveRange: (1, 100))
    var brightness: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Dimme \(\.$room) auf \(\.$brightness) %")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await HueRemote.shared.setBrightness(Double(brightness), groupedLight: room.groupedLightID)
        return .result(dialog: "\(room.name) leuchtet mit \(brightness) %.")
    }
}

struct SetLightPowerIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Lampe schalten"
    static let description = IntentDescription("Schaltet eine einzelne Lampe oder Steckdose an oder aus.")

    @Parameter(title: "Lampe")
    var light: LightEntity?

    @Parameter(title: "An")
    var value: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Schalte \(\.$light) \(\.$value)")
    }

    init() {}

    init(light: LightEntity?) {
        self.light = light
    }

    init(on: Bool) {
        value = on
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let light else { throw $light.needsValueError("Welche Lampe?") }
        try await HueRemote.shared.setOn(value, light: light.id)
        return .result(dialog: "\(light.name) ist \(value ? "an" : "aus").")
    }
}

struct ActivateSceneIntent: AppIntent {
    static let title: LocalizedStringResource = "Szene starten"
    static let description = IntentDescription("Startet eine Hue-Szene in ihrem Raum.")

    @Parameter(title: "Szene")
    var scene: SceneEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Starte \(\.$scene)")
    }

    init() {}

    init(scene: SceneEntity?) {
        self.scene = scene
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let scene else { throw $scene.needsValueError("Welche Szene?") }
        try await HueRemote.shared.recall(scene: scene.id)
        return .result(dialog: "\(scene.name) läuft im Raum \(scene.roomName).")
    }
}

struct AllOffIntent: AppIntent {
    static let title: LocalizedStringResource = "Alle Lichter aus"
    static let description = IntentDescription("Schaltet jedes Licht im Zuhause aus.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await HueRemote.shared.allOff()
        return .result(dialog: "Alle Lichter sind aus. Gute Nacht!")
    }
}

/// "Hey Siri, Hoku Zimmer" — no "an"/"aus", so Siri's Home domain doesn't claim it.
struct ToggleRoomIntent: AppIntent {
    static let title: LocalizedStringResource = "Raum umschalten"
    static let description = IntentDescription("Schaltet einen Raum an, wenn er aus ist, und aus, wenn er an ist.")

    @Parameter(title: "Raum")
    var room: RoomEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let isOn = try await HueRemote.shared.isOn(groupedLight: room.groupedLightID)
        try await HueRemote.shared.setOn(!isOn, groupedLight: room.groupedLightID)
        return .result(dialog: "\(room.name) ist jetzt \(isOn ? "aus" : "an").")
    }
}

struct ToggleLightIntent: AppIntent {
    static let title: LocalizedStringResource = "Lampe umschalten"
    static let description = IntentDescription("Schaltet eine Lampe oder Steckdose um.")

    @Parameter(title: "Lampe")
    var light: LightEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let isOn = try await HueRemote.shared.isOn(light: light.id)
        try await HueRemote.shared.setOn(!isOn, light: light.id)
        return .result(dialog: "\(light.name) ist jetzt \(isOn ? "aus" : "an").")
    }
}

import AppIntents
import HueKit

/// Siri phrases. Apple requires the app name in every phrase; "Hey Siri, Vitrine an"
/// without it only works through Apple Home. Phrases avoid prepositions ("im", "in
/// der"), which Siri matches poorly against entity names.
struct HokuShortcuts: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .orange

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SetRoomPowerIntent(on: true),
            phrases: [
                "\(.applicationName) \(\.$room) an",
                "Schalte \(\.$room) mit \(.applicationName) ein",
                "Mach \(\.$room) mit \(.applicationName) an",
            ],
            shortTitle: "Raum einschalten",
            systemImageName: "lightbulb.fill"
        )
        AppShortcut(
            intent: SetRoomPowerIntent(on: false),
            phrases: [
                "\(.applicationName) \(\.$room) aus",
                "Schalte \(\.$room) mit \(.applicationName) aus",
                "Mach \(\.$room) mit \(.applicationName) aus",
            ],
            shortTitle: "Raum ausschalten",
            systemImageName: "lightbulb"
        )
        AppShortcut(
            intent: SetLightPowerIntent(on: true),
            phrases: [
                "\(.applicationName) \(\.$light) an",
                "Schalte \(\.$light) mit \(.applicationName) ein",
            ],
            shortTitle: "Lampe einschalten",
            systemImageName: "lamp.table.fill"
        )
        AppShortcut(
            intent: SetLightPowerIntent(on: false),
            phrases: [
                "\(.applicationName) \(\.$light) aus",
                "Schalte \(\.$light) mit \(.applicationName) aus",
            ],
            shortTitle: "Lampe ausschalten",
            systemImageName: "lamp.table"
        )
        AppShortcut(
            intent: ToggleRoomIntent(),
            phrases: [
                "\(.applicationName) \(\.$room)",
                "\(.applicationName) schalte \(\.$room)",
            ],
            shortTitle: "Raum umschalten",
            systemImageName: "lightswitch.on"
        )
        AppShortcut(
            intent: ToggleLightIntent(),
            phrases: [
                "\(.applicationName) \(\.$light)",
            ],
            shortTitle: "Lampe umschalten",
            systemImageName: "lamp.table.fill"
        )
        AppShortcut(
            intent: ActivateSceneIntent(),
            phrases: [
                "\(.applicationName) \(\.$scene)",
                "Starte \(\.$scene) mit \(.applicationName)",
                "\(.applicationName) Szene \(\.$scene)",
                "Aktiviere \(\.$scene) mit \(.applicationName)",
            ],
            shortTitle: "Szene starten",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: SetRoomBrightnessIntent(),
            phrases: [
                "Dimme \(\.$room) mit \(.applicationName)",
                "\(.applicationName) \(\.$room) dimmen",
            ],
            shortTitle: "Raum dimmen",
            systemImageName: "sun.max.fill"
        )
        AppShortcut(
            intent: SleepTimerIntent(),
            phrases: [
                "\(.applicationName) Einschlaftimer \(\.$room)",
                "Starte den Einschlaftimer mit \(.applicationName)",
            ],
            shortTitle: "Einschlaf-Timer",
            systemImageName: "moon.zzz.fill"
        )
        AppShortcut(
            intent: AllOffIntent(),
            phrases: [
                "\(.applicationName) alles aus",
                "Alle Lichter aus mit \(.applicationName)",
                "Gute Nacht mit \(.applicationName)",
            ],
            shortTitle: "Alles aus",
            systemImageName: "power"
        )
    }
}

/// Fades a room out over a while. Runs in the app, which also switches the plugs off
/// at the end; the lights themselves fade on the bridge.
struct SleepTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Einschlaf-Timer"
    static let description = IntentDescription("Dimmt einen Raum langsam aus, z. B. zum Einschlafen.")

    @Parameter(title: "Raum")
    var room: RoomEntity

    @Parameter(title: "Minuten", default: 30, inclusiveRange: (1, 100))
    var minutes: Int

    @Dependency private var store: HueStore

    static var parameterSummary: some ParameterSummary {
        Summary("Dimme \(\.$room) in \(\.$minutes) Minuten aus")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        if store.lastSync == nil { await store.refresh() }
        guard let group = store.group(room.id) else {
            throw HueError.bridge(String(localized: "Den Raum \(room.name) gibt es nicht mehr."))
        }
        store.startFadeOut(group, minutes: minutes)
        return .result(dialog: "\(room.name) dimmt in \(minutes) Minuten aus. Schlaf gut!")
    }
}

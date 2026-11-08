import Foundation

/// A voice command Hoku offers as a personal shortcut: its name is what you say to
/// Siri ("Zimmer an"), its URL the `hoku://` command it runs.
public struct SiriCommand: Identifiable, Hashable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case room = "Räume"
        case light = "Lampen"
        case scene = "Szenen"
        case home = "Zuhause"
    }

    /// What the shortcut does, as one of Hoku's own App Intent actions. Preferred over
    /// the URL: Shortcuts runs an app's own action without asking first.
    public enum Action: Hashable, Sendable {
        case roomPower(id: String, name: String, isZone: Bool, on: Bool)
        case lightPower(id: String, name: String, roomName: String?, on: Bool)
        case scene(id: String, name: String, roomName: String)
        case allOff
    }

    public var name: String
    /// `hoku://` fallback for builds without a team identifier (see `SiriCommands`).
    public var url: String
    public var action: Action
    public var kind: Kind
    public var isRecommended: Bool
    /// Another way to say the command `aliasOf` ("Light Strip an" for "Lightstrip an").
    public var aliasOf: String?

    public var id: String { name }
}

extension SiriCommand {
    /// Commands for this home: rooms and zones on/off (recommended), lamps, scenes as
    /// "<Room> <Scene>", "Alles aus" — plus the ways Siri writes names. Names are unique.
    @MainActor
    public static func proposals(for store: HueStore) -> [SiriCommand] {
        var commands: [SiriCommand] = []

        for group in store.sortedRooms + store.sortedZones {
            let name = group.name
            for on in [true, false] {
                commands.append(SiriCommand(
                    name: "\(name) \(on ? "an" : "aus")",
                    url: "hoku://raum/\(encode(name))/\(on ? "an" : "aus")",
                    action: .roomPower(id: group.id, name: name, isZone: group.isZone, on: on),
                    kind: .room, isRecommended: true
                ))
            }
        }

        let roomNames: [String: String] = Dictionary(
            store.sortedRooms.flatMap { room in store.lights(in: room).map { ($0.id, room.name) } },
            uniquingKeysWith: { first, _ in first }
        )
        for light in store.lights.values.sorted(by: { store.name(of: $0) < store.name(of: $1) }) {
            let name = store.name(of: light)
            for on in [true, false] {
                commands.append(SiriCommand(
                    name: "\(name) \(on ? "an" : "aus")",
                    url: "hoku://lampe/\(encode(name))/\(on ? "an" : "aus")",
                    action: .lightPower(id: light.id, name: name, roomName: roomNames[light.id], on: on),
                    kind: .light, isRecommended: false
                ))
            }
        }

        for group in store.sortedRooms + store.sortedZones {
            for scene in store.scenes(in: group) where !scene.name.hasPrefix("Neue Szene") {
                commands.append(SiriCommand(
                    name: "\(group.name) \(scene.name)",
                    url: "hoku://szene/\(encode(scene.name))?raum=\(encode(group.name))",
                    action: .scene(id: scene.id, name: scene.name, roomName: group.name),
                    kind: .scene, isRecommended: false
                ))
            }
        }

        commands.append(SiriCommand(name: "Alles aus", url: "hoku://alle/aus", action: .allOff, kind: .home, isRecommended: true))
        commands.append(SiriCommand(name: "Gute Nacht", url: "hoku://alle/aus", action: .allOff, kind: .home, isRecommended: false))

        commands = withSpokenVariants(commands, store: store)

        // A room and a light can share a name ("Lampe"): keep the first, names must be unique.
        var seen = Set<String>()
        return commands.filter { seen.insert($0.name.lowercased()).inserted }
    }

    /// Adds the ways Siri actually writes names: "Light Strip an" next to "Lightstrip an",
    /// "Vitrine an" next to "Vitrinen an" — unless the variant is another device's name.
    @MainActor private static func withSpokenVariants(_ commands: [SiriCommand], store: HueStore) -> [SiriCommand] {
        let taken = Set((store.sortedRooms + store.sortedZones).map(\.name) + store.lights.values.map { store.name(of: $0) })
        var result: [SiriCommand] = []
        for command in commands {
            result.append(command)
            guard command.kind == .room || command.kind == .light else { continue }
            for verb in [" an", " aus"] where command.name.hasSuffix(verb) {
                let subject = String(command.name.dropLast(verb.count))
                for variant in SpokenNames.variants(of: subject, avoiding: taken) {
                    var alias = command
                    alias.name = variant + verb
                    alias.aliasOf = command.name
                    result.append(alias)
                }
            }
        }
        return result
    }

    private static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/", "?", "&"])) ?? text
    }
}

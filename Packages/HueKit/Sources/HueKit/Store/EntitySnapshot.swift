import Foundation

/// A small, offline-readable list of rooms, lights and scenes for Siri, Shortcuts and
/// Control Center. The app writes it whenever names or structure change; extensions
/// read it instead of querying the bridge for every parameter suggestion.
public struct EntitySnapshot: Codable, Equatable, Sendable {
    public struct Room: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var groupedLightID: String
        public var isZone: Bool
        public var archetype: String?
        /// Other ways to say the name ("Vitrine" for "Vitrinen"), for Siri matching.
        public var synonyms: [String]?
    }

    public struct LightInfo: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var roomName: String?
        public var isDimmable: Bool
        public var synonyms: [String]?
    }

    public struct SceneInfo: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var groupID: String
        public var groupName: String
    }

    public var rooms: [Room]
    public var lights: [LightInfo]
    public var scenes: [SceneInfo]
    public var homeGroupedLightID: String?

    public static let empty = EntitySnapshot(rooms: [], lights: [], scenes: [], homeGroupedLightID: nil)

    static var file: URL { SharedStorage.directory.appending(path: "entities.json") }

    public static func load() -> EntitySnapshot? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(EntitySnapshot.self, from: data)
    }

    public func save() throws {
        try FileManager.default.createDirectory(at: SharedStorage.directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: Self.file, options: .atomic)
    }

    /// Builds a snapshot from raw `GET /clip/v2/resource` data, for when no saved one exists.
    @MainActor
    public static func from(resources: [JSONValue]) -> EntitySnapshot {
        let store = HueStore()
        store.load(resources)
        return store.entitySnapshot
    }
}

extension HueStore {
    public var entitySnapshot: EntitySnapshot {
        let groups = sortedRooms + sortedZones
        let roomNames: [String: String] = Dictionary(
            sortedRooms.flatMap { room in lights(in: room).map { ($0.id, room.name) } },
            uniquingKeysWith: { first, _ in first }
        )
        let allNames = Set(groups.map(\.name) + lights.values.map { name(of: $0) })
        return EntitySnapshot(
            rooms: groups.compactMap { group in
                group.groupedLightID.map {
                    .init(
                        id: group.id, name: group.name, groupedLightID: $0, isZone: group.isZone,
                        archetype: group.metadata?.archetype,
                        synonyms: SpokenNames.variants(of: group.name, avoiding: allNames)
                    )
                }
            },
            lights: lights.values
                .map {
                    .init(
                        id: $0.id, name: name(of: $0), roomName: roomNames[$0.id], isDimmable: $0.supportsDimming,
                        synonyms: SpokenNames.variants(of: name(of: $0), avoiding: allNames)
                    )
                }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
            scenes: groups.flatMap { group in
                scenes(in: group).map { .init(id: $0.id, name: $0.name, groupID: group.id, groupName: group.name) }
            },
            homeGroupedLightID: bridgeHome?.groupedLightID
        )
    }
}

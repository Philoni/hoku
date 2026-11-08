import AppIntents
import HueKit

// Rooms, lights and scenes as App Intents entities. All queries read the snapshot the
// app writes (entities.json), so they are fast and work without the bridge.

struct RoomEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Raum", numericFormat: "\(placeholder: .int) Räume")
    static let defaultQuery = RoomQuery()

    let id: String
    let name: String
    let groupedLightID: String
    let isZone: Bool
    let synonyms: [String]

    init(_ room: EntitySnapshot.Room) {
        id = room.id
        name = room.name
        groupedLightID = room.groupedLightID
        isZone = room.isZone
        synonyms = room.synonyms ?? []
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: isZone ? "Zone" : "Raum",
            image: .init(systemName: isZone ? "square.on.square" : "house.fill"),
            synonyms: synonyms.map { "\($0)" }
        )
    }
}

struct RoomQuery: EntityStringQuery {
    func entities(for identifiers: [RoomEntity.ID]) async throws -> [RoomEntity] {
        try await HueRemote.shared.snapshot().rooms.filter { identifiers.contains($0.id) }.map(RoomEntity.init)
    }

    func entities(matching string: String) async throws -> [RoomEntity] {
        try await HueRemote.shared.snapshot().rooms
            .filter { room in ([room.name] + (room.synonyms ?? [])).contains { $0.localizedStandardContains(string) } }
            .map(RoomEntity.init)
    }

    func suggestedEntities() async throws -> [RoomEntity] {
        try await HueRemote.shared.snapshot().rooms.map(RoomEntity.init)
    }
}

struct LightEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Lampe", numericFormat: "\(placeholder: .int) Lampen")
    static let defaultQuery = LightQuery()

    let id: String
    let name: String
    let roomName: String?
    let synonyms: [String]

    init(_ light: EntitySnapshot.LightInfo) {
        id = light.id
        name = light.name
        roomName = light.roomName
        synonyms = light.synonyms ?? []
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: roomName.map { "\($0)" },
            image: .init(systemName: "lightbulb.fill"),
            synonyms: synonyms.map { "\($0)" }
        )
    }
}

struct LightQuery: EntityStringQuery {
    func entities(for identifiers: [LightEntity.ID]) async throws -> [LightEntity] {
        try await HueRemote.shared.snapshot().lights.filter { identifiers.contains($0.id) }.map(LightEntity.init)
    }

    func entities(matching string: String) async throws -> [LightEntity] {
        try await HueRemote.shared.snapshot().lights
            .filter { light in ([light.name] + (light.synonyms ?? [])).contains { $0.localizedStandardContains(string) } }
            .map(LightEntity.init)
    }

    func suggestedEntities() async throws -> [LightEntity] {
        try await HueRemote.shared.snapshot().lights.map(LightEntity.init)
    }
}

struct SceneEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Szene", numericFormat: "\(placeholder: .int) Szenen")
    static let defaultQuery = SceneQuery()

    let id: String
    let name: String
    let roomName: String

    init(_ scene: EntitySnapshot.SceneInfo) {
        id = scene.id
        name = scene.name
        roomName = scene.groupName
    }

    var displayRepresentation: DisplayRepresentation {
        // Many rooms share scene names ("Entspannen"); the synonyms let you say
        // "Zimmer Entspannen" or "Entspannen im Zimmer" to pick one directly.
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(roomName)",
            image: .init(systemName: "sparkles"),
            synonyms: ["\(roomName) \(name)", "\(name) im \(roomName)", "\(name) in \(roomName)"]
        )
    }
}

struct SceneQuery: EntityStringQuery {
    func entities(for identifiers: [SceneEntity.ID]) async throws -> [SceneEntity] {
        try await HueRemote.shared.snapshot().scenes.filter { identifiers.contains($0.id) }.map(SceneEntity.init)
    }

    func entities(matching string: String) async throws -> [SceneEntity] {
        try await HueRemote.shared.snapshot().scenes
            .filter { "\($0.groupName) \($0.name)".localizedStandardContains(string) || $0.name.localizedStandardContains(string) }
            .map(SceneEntity.init)
    }

    func suggestedEntities() async throws -> [SceneEntity] {
        try await HueRemote.shared.snapshot().scenes.map(SceneEntity.init)
    }
}

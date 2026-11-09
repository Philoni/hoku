import Foundation

/// Stateless bridge commands for Siri, Shortcuts and Control Center. Works in any
/// process (app or extension): credentials come from the shared container and every
/// call goes straight to the bridge.
public actor HueRemote {
    public static let shared = HueRemote()

    private let client = HueClient()

    public init() {}

    private func credentials() throws -> BridgeCredentials {
        guard let credentials = CredentialStore.load() else {
            throw HueError.bridge(String(localized: "Hoku ist noch mit keiner Hue Bridge gekoppelt. Öffne Hoku und koppel deine Bridge.", bundle: .module))
        }
        return credentials
    }

    // MARK: Rooms and zones (grouped lights)

    public func isOn(groupedLight id: String) async throws -> Bool {
        let resource = try await client.resource(credentials(), type: "grouped_light", id: id)
        return resource?["on"]?["on"] == .bool(true)
    }

    public func setOn(_ on: Bool, groupedLight id: String) async throws {
        try await client.update(credentials(), type: "grouped_light", id: id, body: ["on": ["on": .bool(on)]])
    }

    public func setBrightness(_ brightness: Double, groupedLight id: String) async throws {
        let value = min(max(brightness.rounded(), 1), 100)
        try await client.update(credentials(), type: "grouped_light", id: id, body: [
            "on": ["on": true],
            "dimming": ["brightness": .number(value)],
        ])
    }

    // MARK: Lights

    public func isOn(light id: String) async throws -> Bool {
        let resource = try await client.resource(credentials(), type: "light", id: id)
        return resource?["on"]?["on"] == .bool(true)
    }

    public func setOn(_ on: Bool, light id: String) async throws {
        try await client.update(credentials(), type: "light", id: id, body: ["on": ["on": .bool(on)]])
    }

    // MARK: Scenes and everything

    public func recall(scene id: String) async throws {
        try await client.update(credentials(), type: "scene", id: id, body: ["recall": ["action": "active"]])
    }

    public func allOff() async throws {
        let credentials = try credentials()
        var homeID = EntitySnapshot.load()?.homeGroupedLightID
        if homeID == nil {
            homeID = try await snapshot().homeGroupedLightID
        }
        guard let homeID else { throw HueError.bridge(String(localized: "Die Bridge meldet keine Lichtgruppe für das ganze Zuhause.", bundle: .module)) }
        try await client.update(credentials, type: "grouped_light", id: homeID, body: ["on": ["on": false]])
    }

    /// The saved snapshot, or a fresh one from the bridge if none was saved yet.
    public func snapshot() async throws -> EntitySnapshot {
        if let saved = EntitySnapshot.load(), !saved.rooms.isEmpty { return saved }
        let resources = try await client.allResources(credentials())
        return await EntitySnapshot.from(resources: resources)
    }
}

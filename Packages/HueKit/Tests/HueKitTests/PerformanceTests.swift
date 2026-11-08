import Foundation
import Testing
@testable import HueKit

/// Timings on a large synthetic home, so regressions show up as numbers.
/// Run with `swift test -c release --filter PerformanceTests` for realistic values.
@Suite(.serialized) struct PerformanceTests {
    /// A home much bigger than most: 60 lamps in 15 rooms, 3 zones, 8 scenes per room,
    /// plus the connectivity and software-update resources every device brings.
    @MainActor static func largeHome(rooms roomCount: Int = 15, lightsPerRoom: Int = 4, scenesPerRoom: Int = 8) throws -> [JSONValue] {
        let fixture = try HueStoreTests.fixture()
        func template(_ type: String, name: String? = nil) throws -> JSONValue {
            try #require(fixture.first { $0["type"]?.stringValue == type && (name == nil || $0["metadata"]?["name"]?.stringValue == name) })
        }
        let deviceTemplate = try template("device", name: "Floor Lamp")
        let lightTemplate = try #require(fixture.first { $0["type"]?.stringValue == "light" && $0["dimming"] != nil })
        let roomTemplate = try template("room")
        let groupedTemplate = try #require(fixture.first { $0["type"]?.stringValue == "grouped_light" && $0["owner"]?["rtype"]?.stringValue == "room" })
        let sceneTemplate = try template("scene", name: "Tropical")

        var resources = fixture.filter { ["bridge_home", "bridge"].contains($0["type"]?.stringValue ?? "") }
        if let home = fixture.first(where: { $0["owner"]?["rtype"]?.stringValue == "bridge_home" }) {
            resources.append(home)
        }

        func with(_ base: JSONValue, _ patch: JSONValue) -> JSONValue { base.merging(patch) }
        var allLightIDs: [String] = []

        for room in 0..<roomCount {
            let roomID = "room-\(room)"
            let groupedID = "grouped-\(room)"
            var children: [JSONValue] = []
            var roomLights: [String] = []
            for index in 0..<lightsPerRoom {
                let deviceID = "device-\(room)-\(index)"
                let lightID = "light-\(room)-\(index)"
                roomLights.append(lightID)
                children.append(["rid": .string(deviceID), "rtype": "device"])
                resources.append(with(deviceTemplate, [
                    "id": .string(deviceID),
                    "metadata": ["name": .string("Lampe \(room)-\(index)")],
                    "services": [
                        ["rid": .string(lightID), "rtype": "light"],
                        ["rid": .string("zigbee-\(room)-\(index)"), "rtype": "zigbee_connectivity"],
                    ],
                ]))
                resources.append(with(lightTemplate, [
                    "id": .string(lightID),
                    "owner": ["rid": .string(deviceID), "rtype": "device"],
                    "on": ["on": .bool(index.isMultiple(of: 2))],
                ]))
                resources.append([
                    "id": .string("zigbee-\(room)-\(index)"), "type": "zigbee_connectivity",
                    "owner": ["rid": .string(deviceID), "rtype": "device"], "status": "connected",
                ])
                resources.append([
                    "id": .string("update-\(room)-\(index)"), "type": "device_software_update",
                    "owner": ["rid": .string(deviceID), "rtype": "device"], "state": "no_update", "problems": [],
                ])
            }
            allLightIDs += roomLights
            resources.append(with(roomTemplate, [
                "id": .string(roomID),
                "children": .array(children),
                "services": [["rid": .string(groupedID), "rtype": "grouped_light"]],
                "metadata": ["name": .string("Raum \(room)")],
            ]))
            resources.append(with(groupedTemplate, [
                "id": .string(groupedID),
                "owner": ["rid": .string(roomID), "rtype": "room"],
                "on": ["on": .bool(room.isMultiple(of: 2))],
            ]))
            for scene in 0..<scenesPerRoom {
                resources.append(with(sceneTemplate, [
                    "id": .string("scene-\(room)-\(scene)"),
                    "group": ["rid": .string(roomID), "rtype": "room"],
                    "metadata": ["name": .string("Szene \(scene)")],
                    "actions": .array(roomLights.map { id in
                        ["target": ["rid": .string(id), "rtype": "light"], "action": ["on": ["on": true]]]
                    }),
                ]))
            }
        }
        // Zones spanning rooms, so the parent-room logic has work to do.
        for zone in 0..<3 {
            let members = allLightIDs.enumerated().filter { $0.offset % 3 == zone }.map(\.element)
            resources.append([
                "id": .string("zone-\(zone)"), "type": "zone",
                "children": .array(members.map { ["rid": .string($0), "rtype": "light"] }),
                "services": [["rid": .string("zone-grouped-\(zone)"), "rtype": "grouped_light"]],
                "metadata": ["name": .string("Zone \(zone)"), "archetype": "home"],
            ])
            resources.append(with(groupedTemplate, [
                "id": .string("zone-grouped-\(zone)"),
                "owner": ["rid": .string("zone-\(zone)"), "rtype": "zone"],
            ]))
        }
        return resources
    }

    private func measure(_ label: String, iterations: Int = 1, _ body: () throws -> Void) rethrows -> Duration {
        let clock = ContinuousClock()
        let elapsed = try clock.measure {
            for _ in 0..<iterations { try body() }
        }
        let each = elapsed / iterations
        print("⏱ \(label): \(each.formatted(.units(allowed: [.milliseconds, .microseconds], fractionalPart: .show(length: 2)))) each (\(iterations)×)")
        return each
    }

    @Test @MainActor func fullLoad() throws {
        let resources = try Self.largeHome()
        let store = HueStore()
        let each = measure("load \(resources.count) resources", iterations: 10) { store.load(resources) }
        #expect(store.lights.count == 60)
        #expect(store.scenes.count == 120)
        #expect(each < .milliseconds(250))
    }

    @Test @MainActor func eventBurst() throws {
        let store = HueStore()
        store.load(try Self.largeHome())
        let ids = Array(store.lights.keys)
        // What a running dynamic scene produces: brightness and color for every lamp.
        let events = (0..<1000).map { index in
            HueEvent(type: .update, data: [[
                "id": .string(ids[index % ids.count]), "type": "light",
                "dimming": ["brightness": .number(Double(index % 100 + 1))],
                "color": ["xy": ["x": 0.4, "y": .number(0.3 + Double(index % 10) / 100)]],
            ]])
        }
        let each = measure("apply 1000 light events", iterations: 3) { store.apply(events) }
        #expect(each < .milliseconds(500))
    }

    /// Everything the home page computes on each redraw.
    @Test @MainActor func homePageDerivedData() throws {
        let store = HueStore()
        store.load(try Self.largeHome())
        let each = measure("home page derived data", iterations: 50) {
            let rooms = store.sortedRooms
            let zones = store.topLevelZones
            for group in rooms + zones {
                _ = store.lights(in: group)
                _ = store.colors(in: group)
                _ = store.activeScene(in: group)
                _ = store.groupedLight(for: group)
            }
            _ = store.lightsOnCount
        }
        #expect(each < .milliseconds(50))
    }

    @Test @MainActor func entitySnapshot() throws {
        let store = HueStore()
        store.load(try Self.largeHome())
        let each = measure("entity snapshot for Siri", iterations: 20) { _ = store.entitySnapshot }
        #expect(each < .milliseconds(100))
    }
}

private extension HueStore {
    /// Mirrors the app's `colors(for:)` (which lives in the app target).
    func colors(in group: HueGroup) -> [Bool] {
        lights(in: group).map(\.isOn)
    }
}

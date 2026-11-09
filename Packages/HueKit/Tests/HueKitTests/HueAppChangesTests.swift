import Foundation
import Observation
import Testing
@testable import HueKit

/// What happens when the home changes elsewhere — renamed, added, moved or removed in
/// the Hue app — as the event stream reports it.
@Suite @MainActor struct HueAppChangesTests {
    func loadedStore() throws -> HueStore {
        let store = HueStore()
        store.load(try HueStoreTests.fixture())
        return store
    }

    func floorLampDevice(_ store: HueStore) throws -> Device {
        let lamp = try #require(store.findLight(named: "Floor Lamp"))
        return try #require(lamp.owner.flatMap { store.devices[$0.rid] })
    }

    // MARK: Renaming

    @Test func renamedLampShowsNewNameAtOnce() throws {
        let store = try loadedStore()
        let device = try floorLampDevice(store)
        store.apply([HueEvent(type: .update, data: [["id": .string(device.id), "type": "device", "metadata": ["name": "Stehlampe"]]])])
        let lamp = try #require(store.findLight(named: "Stehlampe"))
        #expect(store.name(of: lamp) == "Stehlampe")
        // Other metadata survives the partial update.
        #expect(store.archetype(of: lamp) == "floor_shade")
    }

    @Test func oldNameKeepsWorkingAfterRename() throws {
        let store = try loadedStore()
        let before = store.entitySnapshot
        let device = try floorLampDevice(store)
        let lampID = try #require(store.findLight(named: "Floor Lamp")).id
        let roomID = try #require(store.findGroup(named: "Living Room")).id

        store.apply([HueEvent(type: .update, data: [
            ["id": .string(device.id), "type": "device", "metadata": ["name": "Stehlampe"]],
            ["id": .string(roomID), "type": "room", "metadata": ["name": "Wohnzimmer"]],
        ])])
        let after = store.entitySnapshot
        let changed = store.nameHistory.recordRenames(from: before, to: after)
        #expect(changed)

        // A shortcut saying "Floor Lamp an" still reaches the same lamp, tolerantly matched.
        #expect(store.findLight(named: "Floor Lamp")?.id == lampID)
        #expect(store.findLight(named: "floorlamp")?.id == lampID)
        #expect(store.findGroup(named: "Living Room")?.id == roomID)
        #expect(store.findGroup(named: "Wohnzimmer")?.id == roomID)
    }

    @Test func currentNamesWinOverFormerOnes() throws {
        let store = try loadedStore()
        let before = store.entitySnapshot
        let floorDevice = try floorLampDevice(store)
        let plug = try #require(store.findLight(named: "Cabinet Plug"))
        let plugDevice = try #require(plug.owner?.rid)

        // Floor Lamp → Stehlampe, then the plug takes the name "Floor Lamp".
        store.apply([HueEvent(type: .update, data: [["id": .string(floorDevice.id), "type": "device", "metadata": ["name": "Stehlampe"]]])])
        store.nameHistory.recordRenames(from: before, to: store.entitySnapshot)
        let middle = store.entitySnapshot
        store.apply([HueEvent(type: .update, data: [["id": .string(plugDevice), "type": "device", "metadata": ["name": "Floor Lamp"]]])])
        store.nameHistory.recordRenames(from: middle, to: store.entitySnapshot)

        #expect(store.findLight(named: "Floor Lamp")?.id == plug.id)
        // And the plug's old name now points to the plug.
        #expect(store.findLight(named: "Cabinet Plug")?.id == plug.id)
    }

    @Test func historySurvivesAsFileFormat() throws {
        var history = NameHistory()
        history.record(id: "a", oldName: "Vitrinen", newName: "Vitrine")
        let data = try JSONEncoder().encode(history)
        let decoded = try JSONDecoder().decode(NameHistory.self, from: data)
        #expect(decoded == history)
        #expect(decoded.formerNames["a"] == ["Vitrinen"])
    }

    @Test func deletedItemsAreForgotten() throws {
        var history = NameHistory()
        let old = EntitySnapshot(rooms: [], lights: [.init(id: "a", name: "Alt", isDimmable: true)], scenes: [], homeGroupedLightID: nil)
        let renamed = EntitySnapshot(rooms: [], lights: [.init(id: "a", name: "Neu", isDimmable: true)], scenes: [], homeGroupedLightID: nil)
        history.recordRenames(from: old, to: renamed)
        #expect(history.formerNames["a"] == ["Alt"])
        history.recordRenames(from: renamed, to: .empty)
        #expect(history.formerNames.isEmpty)
    }

    // MARK: Adding, moving, removing

    @Test func newLampAppearsInItsRoom() throws {
        let store = try loadedStore()
        let room = try #require(store.findGroup(named: "Living Room"))
        let template = try #require(store.raw.values.first { $0["type"]?.stringValue == "light" && $0["dimming"] != nil })

        store.apply([
            HueEvent(type: .add, data: [
                ["id": "new-device", "type": "device", "metadata": ["name": "Neue Lampe", "archetype": "classic_bulb"],
                 "services": [["rid": "new-light", "rtype": "light"]]],
                template.merging(["id": "new-light", "owner": ["rid": "new-device", "rtype": "device"]]),
            ]),
            HueEvent(type: .update, data: [
                ["id": .string(room.id), "type": "room",
                 "children": .array((room.children ?? []).map { ["rid": .string($0.rid), "rtype": .string($0.rtype)] } + [["rid": "new-device", "rtype": "device"]])],
            ]),
        ])
        let updatedRoom = try #require(store.group(room.id))
        #expect(store.lights(in: updatedRoom).map { store.name(of: $0) }.contains("Neue Lampe"))
        // Adds trigger a full reload shortly after, in case events arrived incomplete.
        #expect(store.isResyncPending)
    }

    @Test func lampMovedOutOfRoom() throws {
        let store = try loadedStore()
        let room = try #require(store.findGroup(named: "Living Room"))
        let device = try floorLampDevice(store)
        let remaining = (room.children ?? []).filter { $0.rid != device.id }
        store.apply([HueEvent(type: .update, data: [
            ["id": .string(room.id), "type": "room",
             "children": .array(remaining.map { ["rid": .string($0.rid), "rtype": .string($0.rtype)] })],
        ])])
        let updatedRoom = try #require(store.group(room.id))
        #expect(store.lights(in: updatedRoom).count == 1)
        // A plain update needs no reload.
        #expect(!store.isResyncPending)
    }

    @Test func deletedRoomAndSceneDisappear() throws {
        let store = try loadedStore()
        let room = try #require(store.findGroup(named: "Living Room"))
        let scene = try #require(store.findScene(named: "Relax"))
        store.apply([HueEvent(type: .delete, data: [
            ["id": .string(scene.id), "type": "scene"],
            ["id": .string(room.id), "type": "room"],
        ])])
        #expect(store.group(room.id) == nil)
        #expect(store.scenes[scene.id] == nil)
        #expect(store.findGroup(named: "Living Room") == nil)
        #expect(store.isResyncPending)
    }

    @Test func updateForUnknownResourceSchedulesReload() throws {
        let store = try loadedStore()
        store.apply([HueEvent(type: .update, data: [["id": "unknown-light", "type": "light", "on": ["on": true]]])])
        #expect(store.lights["unknown-light"] == nil)
        #expect(store.isResyncPending)
    }

    // MARK: Redraws

    @Test func unchangedValuesDoNotNotifyViews() throws {
        let store = try loadedStore()
        let lamp = try #require(store.findLight(named: "Floor Lamp"))
        let flag = Flag()
        withObservationTracking { _ = store.lights } onChange: { flag.raise() }
        // The bridge echoes the state we already have.
        store.apply([HueEvent(type: .update, data: [
            ["id": .string(lamp.id), "type": "light", "on": ["on": .bool(lamp.isOn)]],
        ])])
        #expect(!flag.isRaised)

        store.apply([HueEvent(type: .update, data: [
            ["id": .string(lamp.id), "type": "light", "on": ["on": .bool(!lamp.isOn)]],
        ])])
        #expect(flag.isRaised)
    }

    @Test func identicalReloadDoesNotNotifyViews() throws {
        let store = try loadedStore()
        let flag = Flag()
        withObservationTracking {
            _ = store.lights
            _ = store.rooms
            _ = store.scenes
        } onChange: { flag.raise() }
        store.load(try HueStoreTests.fixture())
        #expect(!flag.isRaised)
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false

    var isRaised: Bool { lock.withLock { raised } }

    func raise() { lock.withLock { raised = true } }
}

@Suite @MainActor struct ReachabilityTests {
    @Test func lampSwitchedOffAtTheWallIsUnreachable() throws {
        let store = HueStore()
        store.load(try HueStoreTests.fixture())
        let lamp = try #require(store.findLight(named: "Floor Lamp"))
        let device = try #require(lamp.owner?.rid)
        #expect(store.isReachable(lamp))
        store.apply([HueEvent(type: .add, data: [
            ["id": "zb-1", "type": "zigbee_connectivity", "owner": ["rid": .string(device), "rtype": "device"], "status": "connectivity_issue"],
        ])])
        #expect(!store.isReachable(lamp))
        store.apply([HueEvent(type: .update, data: [["id": "zb-1", "type": "zigbee_connectivity", "status": "connected"]])])
        #expect(store.isReachable(lamp))
    }
}

@Suite @MainActor struct AmbiguousSceneTests {
    @Test func sceneWithoutRoomPrefersARoomThatIsOn() throws {
        let store = HueStore()
        store.load(try PerformanceTests.largeHome(rooms: 4))
        // Every room has "Szene 0"; rooms 0 and 2 are on, 1 and 3 off.
        for _ in 0..<5 {
            #expect(store.findScene(named: "Szene 0")?.group?.rid == "room-0")
        }
        let room0 = try #require(store.group("room-0"))
        store.setOn(false, group: room0)
        #expect(store.findScene(named: "Szene 0")?.group?.rid == "room-2")
        // With a room given, that room's scene is used.
        let room3 = try #require(store.group("room-3"))
        #expect(store.findScene(named: "Szene 0", in: room3)?.group?.rid == "room-3")
    }
}

@Suite @MainActor struct SmartHomeLinkTests {
    @Test func detectsAppleHomeViaHomeKitOrMatter() throws {
        let store = HueStore()
        store.load(try HueStoreTests.fixture())
        #expect(store.smartHomeLinks == .none)

        store.apply([HueEvent(type: .add, data: [["id": "hk", "type": "homekit", "status": "unpaired"]])])
        #expect(!store.smartHomeLinks.hasAppleHome)
        store.apply([HueEvent(type: .update, data: [["id": "hk", "type": "homekit", "status": "paired"]])])
        #expect(store.smartHomeLinks.hasAppleHome)

        let matterOnly = HueStore()
        matterOnly.load(try HueStoreTests.fixture() + [
            ["id": "mf1", "type": "matter_fabric", "status": "paired", "fabric_data": ["label": "Google", "vendor_id": 24582]],
            ["id": "mf2", "type": "matter_fabric", "status": "timedout", "fabric_data": ["label": "Apple", "vendor_id": 4937]],
        ])
        #expect(matterOnly.smartHomeLinks.matter == [.google])
        #expect(!matterOnly.smartHomeLinks.hasAppleHome)
    }
}

/// Switching single lamps inside an unfolded room card: the room must follow its lamps
/// at once and not blink when the bridge reports in-between states while a lamp fades.
@Suite @MainActor struct RoomFollowsLampsTests {
    @Test func roomTurnsOnAndOffWithItsLampWithoutFlicker() throws {
        let store = HueStore()
        store.load(try HueStoreTests.fixture())
        let room = try #require(store.findGroup(named: "Living Room"))
        let groupedID = try #require(room.groupedLightID)
        let lamp = try #require(store.findLight(named: "Floor Lamp"))
        #expect(store.groupedLights[groupedID]?.isOn == false)

        store.setOn(true, light: lamp)
        #expect(store.groupedLights[groupedID]?.isOn == true)
        // The bridge's lagging report for the group must not switch the card back.
        store.apply([HueEvent(type: .update, data: [["id": .string(groupedID), "type": "grouped_light", "on": ["on": false]]])])
        #expect(store.groupedLights[groupedID]?.isOn == true)

        let lit = try #require(store.lights[lamp.id])
        store.setOn(false, light: lit)
        #expect(store.groupedLights[groupedID]?.isOn == false)
        // While the lamp fades, the bridge briefly reports the group as on again.
        store.apply([HueEvent(type: .update, data: [["id": .string(groupedID), "type": "grouped_light", "on": ["on": true]]])])
        #expect(store.groupedLights[groupedID]?.isOn == false)
    }

    /// Off and quickly on again: the bridge's late "room at 0 %" from switching off lands
    /// after the lamp is on again, and must not empty the room's bar for a second.
    @Test func roomBrightnessFollowsLampWithoutDipping() throws {
        let store = HueStore()
        store.load(try HueStoreTests.fixture())
        let room = try #require(store.findGroup(named: "Living Room"))
        let groupedID = try #require(room.groupedLightID)
        let lamp = try #require(store.findLight(named: "Floor Lamp"))
        let level = lamp.brightness

        store.setOn(true, light: lamp)
        #expect(store.groupedLights[groupedID]?.dimming?.brightness == level)
        store.setOn(false, light: try #require(store.lights[lamp.id]))
        store.setOn(true, light: try #require(store.lights[lamp.id]))
        store.apply([HueEvent(type: .update, data: [["id": .string(groupedID), "type": "grouped_light", "dimming": ["brightness": 0]]])])
        #expect(store.groupedLights[groupedID]?.isOn == true)
        #expect(store.groupedLights[groupedID]?.dimming?.brightness == level)
    }

    @Test func roomStaysOnWhileAnotherLampIsOn() throws {
        let store = HueStore()
        store.load(try HueStoreTests.fixture())
        let room = try #require(store.findGroup(named: "Living Room"))
        let groupedID = try #require(room.groupedLightID)
        let lamp = try #require(store.findLight(named: "Floor Lamp"))
        let plug = try #require(store.findLight(named: "Cabinet Plug"))

        store.setOn(true, light: lamp)
        store.setOn(true, light: plug)
        store.setOn(false, light: try #require(store.lights[lamp.id]))
        #expect(store.groupedLights[groupedID]?.isOn == true)
    }
}

@Suite @MainActor struct DemoHomeTests {
    @Test func demoHomeDecodesCompletely() {
        let store = HueStore()
        store.showDemo()
        #expect(store.sortedRooms.map(\.name) == ["Büro", "Flur", "Küche", "Schlafzimmer", "Wohnzimmer"])
        #expect(store.lights.count == 12)
        #expect(store.scenes.count == 15)
        #expect(store.deviceIssues.isEmpty)
        #expect(store.sortedRooms.allSatisfy { store.groupedLight(for: $0) != nil && !store.lights(in: $0).isEmpty })
        let living = store.findGroup(named: "Wohnzimmer")
        #expect(living.flatMap { store.activeScene(in: $0) }?.name == "Sonnenuntergang")
        #expect(store.credentials?.name == "Hue Bridge · Demo")
    }
}

@Suite @MainActor struct GroupOrderTests {
    private func demoRooms() -> (HueStore, [String: String]) {
        let store = HueStore()
        store.showDemo()
        return (store, Dictionary(uniqueKeysWithValues: store.rooms.values.map { ($0.name, $0.id) }))
    }

    @Test func pinnedRoomsComeFirstInNameOrder() {
        let (store, ids) = demoRooms()
        store.groupOrder.togglePin(ids["Wohnzimmer"]!)
        store.groupOrder.togglePin(ids["Küche"]!)
        #expect(store.sortedRooms.map(\.name) == ["Küche", "Wohnzimmer", "Büro", "Flur", "Schlafzimmer"])
        store.groupOrder.togglePin(ids["Küche"]!)
        #expect(store.sortedRooms.map(\.name) == ["Wohnzimmer", "Büro", "Flur", "Küche", "Schlafzimmer"])
    }

    @Test func movingSwapsNeighboursAndStopsAtTheEdges() {
        let (store, ids) = demoRooms()
        let rooms = Array(store.rooms.values)
        store.groupOrder.move(ids["Flur"]!, up: true, in: rooms)
        #expect(store.sortedRooms.map(\.name) == ["Flur", "Büro", "Küche", "Schlafzimmer", "Wohnzimmer"])
        store.groupOrder.move(ids["Flur"]!, up: true, in: rooms)
        #expect(store.sortedRooms.first?.name == "Flur")
        #expect(!store.groupOrder.canMove(ids["Flur"]!, up: true, in: rooms))
        #expect(!store.groupOrder.canMove(ids["Wohnzimmer"]!, up: false, in: rooms))
    }

    @Test func movesStayInsideThePinnedBlock() {
        let (store, ids) = demoRooms()
        let rooms = Array(store.rooms.values)
        store.groupOrder.togglePin(ids["Wohnzimmer"]!)
        #expect(!store.groupOrder.canMove(ids["Büro"]!, up: true, in: rooms))
        store.groupOrder.move(ids["Büro"]!, up: true, in: rooms)
        #expect(store.sortedRooms.map(\.name) == ["Wohnzimmer", "Büro", "Flur", "Küche", "Schlafzimmer"])
    }

    @Test func roomsAddedLaterFollowByName() {
        var order = GroupOrder()
        order.sequence = ["unknown-b", "unknown-a"]
        let (store, _) = demoRooms()
        #expect(order.sorted(Array(store.rooms.values)).map(\.name) == ["Büro", "Flur", "Küche", "Schlafzimmer", "Wohnzimmer"])
        #expect(order.isCustom)
    }

    @Test func survivesSavingAndLoading() throws {
        var order = GroupOrder()
        order.togglePin("a")
        order.sequence = ["b", "a"]
        #expect(try JSONDecoder().decode(GroupOrder.self, from: JSONEncoder().encode(order)) == order)
    }
}

@Suite @MainActor struct EntertainmentAreaTests {
    private func area(status: String) -> JSONValue {
        ["id": "area-1", "type": "entertainment_configuration", "metadata": ["name": "Musik"], "status": .string(status)]
    }

    @Test func showsAnAreaOnlyWhileItStreams() {
        let store = HueStore()
        store.load([area(status: "inactive")])
        #expect(store.streamingAreas.isEmpty)
        store.apply([HueEvent(type: .update, data: [["id": "area-1", "type": "entertainment_configuration", "status": "active"]])])
        #expect(store.streamingAreas.map(\.name) == ["Musik"])
        store.apply([HueEvent(type: .update, data: [["id": "area-1", "type": "entertainment_configuration", "status": "inactive"]])])
        #expect(store.streamingAreas.isEmpty)
    }

    @Test func stoppingHidesItRightAway() {
        let store = HueStore()
        store.load([area(status: "active")])
        store.stopStreaming(store.streamingAreas[0])
        #expect(store.streamingAreas.isEmpty)
    }
}

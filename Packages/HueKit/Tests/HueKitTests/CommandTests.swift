import Foundation
import Testing
@testable import HueKit

@Suite struct URLCommandParsingTests {
    func parse(_ string: String) -> URLCommand? {
        URL(string: string).flatMap(URLCommand.init(url:))
    }

    @Test func germanAndEnglishVerbs() {
        #expect(parse("hoku://raum/Wohnzimmer/an") == .group(name: "Wohnzimmer", action: .on, brightness: nil))
        #expect(parse("hoku://room/Bedroom/off") == .group(name: "Bedroom", action: .off, brightness: nil))
        #expect(parse("hoku://lampe/Stehlampe/umschalten") == .light(name: "Stehlampe", action: .toggle, brightness: nil))
        #expect(parse("hoku://light/Desk/toggle") == .light(name: "Desk", action: .toggle, brightness: nil))
        #expect(parse("hoku://alle/aus") == .allOff)
        #expect(parse("hoku://oeffnen") == .openPanel)
        #expect(parse("hoku://schliessen") == .closePanel)
        #expect(parse("hoku://einrichtung") == .openSetup)
    }

    @Test func brightnessAndEncodedNames() {
        #expect(parse("hoku://raum/Wohnzimmer/an?helligkeit=40") == .group(name: "Wohnzimmer", action: .on, brightness: 40))
        #expect(parse("hoku://lampe/Light%20Strip/an?brightness=5") == .light(name: "Light Strip", action: .on, brightness: 5))
        // A missing verb means "on".
        #expect(parse("hoku://raum/K%C3%BCche") == .group(name: "Küche", action: .on, brightness: nil))
    }

    @Test func scenesWithRoomAndMode() {
        #expect(parse("hoku://szene/Entspannen?raum=Zimmer&modus=dynamisch") == .scene(name: "Entspannen", group: "Zimmer", mode: .dynamic))
        #expect(parse("hoku://scene/Relax?room=Bedroom&mode=static") == .scene(name: "Relax", group: "Bedroom", mode: .static))
        #expect(parse("hoku://szene/Lesen") == .scene(name: "Lesen", group: nil, mode: .active))
    }

    @Test func rejectsNonsense() {
        #expect(parse("https://example.com/raum/x/an") == nil)
        #expect(parse("hoku://raum/Wohnzimmer/explodieren") == nil)
        #expect(parse("hoku://unbekannt") == nil)
        #expect(parse("hoku://szene") == nil)
        // There is no "all on": it must not do the opposite.
        #expect(parse("hoku://alle/an") == nil)
        #expect(parse("hoku://all/on") == nil)
        #expect(parse("hoku://alle") == .allOff)
        #expect(parse("hoku://all/off") == .allOff)
    }
}

@Suite @MainActor struct URLCommandRunTests {
    func loadedStore() throws -> HueStore {
        let store = HueStore()
        store.load(try HueStoreTests.fixture())
        return store
    }

    @Test func reportsWhatItCannotFind() throws {
        let store = try loadedStore()
        #expect(URLCommand.group(name: "Dachboden", action: .on, brightness: nil).run(on: store) == "Raum „Dachboden“ nicht gefunden.")
        #expect(URLCommand.light(name: "Gibtsnicht", action: .on, brightness: nil).run(on: store) == "Lampe „Gibtsnicht“ nicht gefunden.")
        #expect(URLCommand.scene(name: "Disco", group: nil, mode: .active).run(on: store) == "Szene „Disco“ nicht gefunden.")
    }

    @Test func switchesTolerantlyNamedTargets() throws {
        let store = try loadedStore()
        let lamp = try #require(store.findLight(named: "Floor Lamp"))
        #expect(!lamp.isOn)
        #expect(URLCommand.light(name: "floorlamp", action: .on, brightness: nil).run(on: store) == nil)
        #expect(store.lights[lamp.id]?.isOn == true)
        #expect(URLCommand.light(name: "Floor Lamp", action: .toggle, brightness: nil).run(on: store) == nil)
        #expect(store.lights[lamp.id]?.isOn == false)
    }
}

@Suite @MainActor struct SiriCommandProposalTests {
    @Test func proposesRoomsLampsScenesAndHome() throws {
        let store = HueStore()
        store.load(try HueStoreTests.fixture())
        let commands = SiriCommand.proposals(for: store)
        let names = commands.map(\.name)

        #expect(names.contains("Living Room an"))
        #expect(names.contains("Living Room aus"))
        #expect(names.contains("Floor Lamp an"))
        #expect(names.contains("Living Room Relax"))
        #expect(names.contains("Alles aus"))
        // Names are what Siri listens for, so they must be unique.
        #expect(Set(names.map { $0.lowercased() }).count == names.count)
        // Rooms and "Alles aus" are preselected; lamps and scenes are optional.
        #expect(commands.first { $0.name == "Living Room an" }?.isRecommended == true)
        #expect(commands.first { $0.name == "Floor Lamp an" }?.isRecommended == false)
        #expect(commands.first { $0.name == "Living Room an" }?.url == "hoku://raum/Living%20Room/an")
    }

    @Test func addsSpokenVariantsAsAliases() throws {
        let store = HueStore()
        store.load(try HueStoreTests.fixture())
        let device = try #require(store.findLight(named: "Floor Lamp")?.owner?.rid)
        store.apply([HueEvent(type: .update, data: [["id": .string(device), "type": "device", "metadata": ["name": "Lightstrip"]]])])
        let commands = SiriCommand.proposals(for: store)
        let alias = try #require(commands.first { $0.name == "Light Strip an" })
        #expect(alias.aliasOf == "Lightstrip an")
        #expect(alias.url == "hoku://lampe/Lightstrip/an")
    }
}

@Suite @MainActor struct RelativeDimmingTests {
    @Test func dimmingDownNeverSwitchesOn() throws {
        let store = HueStore()
        store.load(try HueStoreTests.fixture())
        let room = try #require(store.findGroup(named: "Living Room"))
        #expect(store.groupedLight(for: room)?.isOn == false)
        store.adjustBrightness(by: -10, group: room)
        #expect(store.groupedLight(for: room)?.isOn == false)
        store.adjustBrightness(by: 10, group: room)
        #expect(store.groupedLight(for: room)?.isOn == true)
        #expect(store.groupedLight(for: room)?.dimming?.brightness == 10)
    }
}

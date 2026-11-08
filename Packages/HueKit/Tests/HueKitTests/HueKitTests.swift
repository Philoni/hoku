import Foundation
import Testing
@testable import HueKit

// MARK: - JSON merging

@Suite struct JSONValueTests {
    @Test func deepMergeKeepsUntouchedFields() throws {
        let base: JSONValue = ["id": "a", "on": ["on": false], "dimming": ["brightness": 40, "min_dim_level": 0.2]]
        let merged = base.merging(["dimming": ["brightness": 80]])
        #expect(merged["dimming"]?["brightness"] == .number(80))
        #expect(merged["dimming"]?["min_dim_level"] == .number(0.2))
        #expect(merged["on"]?["on"] == .bool(false))
    }

    @Test func arraysAreReplacedNotMerged() {
        let base: JSONValue = ["points": [1, 2, 3]]
        #expect(base.merging(["points": [9]])["points"] == [9])
    }

    @Test func boolsStayBools() throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"a":true,"b":1}"#.utf8))
        #expect(value["a"] == .bool(true))
        #expect(value["b"] == .number(1))
    }
}

// MARK: - Event stream parsing

@Suite struct SSEParserTests {
    @Test func parsesMessageOnBlankLine() {
        var parser = SSEParser()
        #expect(parser.consume(": hi").isEmpty)
        #expect(parser.consume("id: 1700000000:0").isEmpty)
        #expect(parser.consume(#"data: [{"creationtime":"2026-10-14T00:00:00Z","id":"e1","type":"update","data":[{"id":"l1","type":"light","on":{"on":true}}]}]"#).isEmpty)
        let events = parser.consume("")
        #expect(events.count == 1)
        #expect(events.first?.type == .update)
        #expect(events.first?.data.first?["on"]?["on"] == .bool(true))
        #expect(parser.lastEventID == "1700000000:0")
    }

    @Test func handlesCRLFAndUnknownEventTypes() {
        var parser = SSEParser()
        _ = parser.consume(#"data: [{"id":"e","type":"something_new","data":[]}]"# + "\r")
        let events = parser.consume("\r")
        #expect(events.first?.type == .unknown)
    }

    @Test func ignoresGarbage() {
        var parser = SSEParser()
        _ = parser.consume("data: not json")
        #expect(parser.consume("").isEmpty)
    }
}

// MARK: - Color math

@Suite struct ColorMathTests {
    let gamutC = ColorMath.fallbackGamut

    @Test func pureRedIsTheSRGBPrimary() {
        // sRGB red (0.64, 0.33) lies inside gamut C, so it must not be clamped.
        let xy = ColorMath.xy(from: RGB(red: 1, green: 0, blue: 0), gamut: gamutC)
        #expect(abs(xy.x - 0.64) < 0.002)
        #expect(abs(xy.y - 0.33) < 0.002)
    }

    @Test func gamutAClampsSaturatedGreen() {
        let gamutA = Gamut(red: XY(x: 0.704, y: 0.296), green: XY(x: 0.2151, y: 0.7106), blue: XY(x: 0.138, y: 0.08))
        let xy = ColorMath.xy(from: RGB(red: 0, green: 1, blue: 0), gamut: gamutA)
        #expect(ColorMath.isInside(xy, gamutA) || abs(xy.x - 0.2151) < 0.1)
    }

    @Test func whiteIsNearD65() {
        let xy = ColorMath.xy(from: .white)
        #expect(abs(xy.x - 0.3127) < 0.005)
        #expect(abs(xy.y - 0.3290) < 0.005)
    }

    @Test func blackDoesNotProduceNaN() {
        let xy = ColorMath.xy(from: RGB(red: 0, green: 0, blue: 0))
        #expect(!xy.x.isNaN && !xy.y.isNaN)
    }

    @Test func outOfGamutPointsAreClampedInside() {
        let clamped = ColorMath.clamp(XY(x: 0.05, y: 0.9), to: gamutC)
        #expect(ColorMath.isInside(XY(x: clamped.x - 0.0001, y: clamped.y - 0.0001), gamutC) || ColorMath.isInside(clamped, gamutC))
        #expect(ColorMath.isInside(XY(x: 0.33, y: 0.33), gamutC))
    }

    @Test func roundTripKeepsHue() {
        let original = RGB(red: 0.1, green: 0.4, blue: 1)
        let back = ColorMath.rgb(from: ColorMath.xy(from: original, gamut: gamutC))
        #expect(back.blue > back.red && back.blue > back.green)
    }

    @Test func mirekKelvinConversion() {
        #expect(ColorMath.mirek(fromKelvin: 2700) == 370)
        #expect(abs(ColorMath.kelvin(fromMirek: 153) - 6536) < 1)
        let warm = ColorMath.rgb(fromMirek: 500)
        #expect(warm.red > warm.blue)
    }
}

// MARK: - Store against a real (anonymized) bridge snapshot

@MainActor
@Suite struct HueStoreTests {
    static func fixture() throws -> [JSONValue] {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/resources", withExtension: "json"))
        return try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: url)).data
    }

    func loadedStore() throws -> HueStore {
        let store = HueStore()
        try store.load(Self.fixture())
        return store
    }

    @Test func decodesRealBridgeData() throws {
        let store = try loadedStore()
        #expect(store.lights.count == 2)
        #expect(store.rooms.count == 1)
        #expect(store.bridgeHome != nil)

        let room = try #require(store.findGroup(named: "living room"))
        #expect(store.lights(in: room).count == 2)
        #expect(store.groupedLight(for: room) != nil)
        #expect(store.scenes(in: room).map(\.name) == ["Relax", "Tropical"])
        #expect(store.findScene(named: "tropical")?.supportsDynamic == true)

        let plug = try #require(store.findLight(named: "Cabinet Plug"))
        #expect(!plug.supportsDimming)
        let lamp = try #require(store.findLight(named: "Floor Lamp"))
        #expect(lamp.supportsColor && lamp.supportsColorTemperature)
        #expect(lamp.effectsV2?.action?.effectValues?.contains("candle") == true)
    }

    @Test func appliesPartialUpdatesFromEventStream() throws {
        let store = try loadedStore()
        let lamp = try #require(store.findLight(named: "Floor Lamp"))
        store.apply([HueEvent(type: .update, data: [
            ["id": .string(lamp.id), "type": "light", "on": ["on": true], "dimming": ["brightness": 66]],
        ])])
        let updated = try #require(store.lights[lamp.id])
        #expect(updated.isOn)
        #expect(updated.brightness == 66)
        // Untouched capabilities survive the partial update.
        #expect(updated.color?.gamut != nil)
    }

    @Test func handlesAddAndDelete() throws {
        let store = try loadedStore()
        let plug = try #require(store.findLight(named: "Cabinet Plug"))
        store.apply([HueEvent(type: .delete, data: [["id": .string(plug.id), "type": "light"]])])
        #expect(store.lights[plug.id] == nil)

        store.apply([HueEvent(type: .add, data: [["id": "new-light", "type": "light", "on": ["on": true]]])])
        #expect(store.lights["new-light"]?.isOn == true)
    }

    @Test func updatesForUnknownResourcesAreIgnored() throws {
        let store = try loadedStore()
        store.apply([HueEvent(type: .update, data: [["id": "nope", "type": "light", "on": ["on": true]]])])
        #expect(store.lights["nope"] == nil)
    }
}

// MARK: - Throttle

@Suite struct CommandThrottleTests {
    actor Recorder {
        var sent: [(Date, JSONValue)] = []
        func record(_ body: JSONValue) { sent.append((.now, body)) }
    }

    @Test func coalescesBurstAndKeepsLatestValue() async throws {
        let recorder = Recorder()
        let throttle = CommandThrottle { _, body in await recorder.record(body) }
        let target = CommandThrottle.Target(type: "light", id: "l1")

        for brightness in 1...20 {
            await throttle.submit(["dimming": ["brightness": .number(Double(brightness))]], to: target)
        }
        await throttle.submit(["on": ["on": true]], to: target)
        try await Task.sleep(for: .milliseconds(500))

        let sent = await recorder.sent
        #expect(sent.count == 2)
        #expect(sent.first?.1["dimming"]?["brightness"] == .number(1))
        // The trailing command merges everything that queued up, latest values winning.
        #expect(sent.last?.1["dimming"]?["brightness"] == .number(20))
        #expect(sent.last?.1["on"]?["on"] == .bool(true))
    }

    @Test func spacesGroupCommands() async throws {
        let recorder = Recorder()
        let throttle = CommandThrottle { _, body in await recorder.record(body) }
        let target = CommandThrottle.Target(type: "grouped_light", id: "g1")

        await throttle.submit(["dimming": ["brightness": 10]], to: target)
        try await Task.sleep(for: .milliseconds(50))
        await throttle.submit(["dimming": ["brightness": 20]], to: target)
        try await Task.sleep(for: .milliseconds(900))

        let sent = await recorder.sent
        #expect(sent.count == 2)
        let gap = sent[1].0.timeIntervalSince(sent[0].0)
        #expect(gap >= 0.4)
    }
}

// MARK: - Usage learning

@Suite struct UsageLogTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        // October 2026: the 12th is a Monday, the 17th a Saturday.
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func prefersScenesUsedAtThisTimeOfDay() {
        var log = UsageLog()
        log.record(sceneID: "nightlight", at: date(12, 23))
        log.record(sceneID: "nightlight", at: date(13, 23, 30))
        log.record(sceneID: "energize", at: date(13, 7))
        log.record(sceneID: "energize", at: date(14, 7, 15))

        let night = log.scores(at: date(15, 23, 10), calendar: calendar)
        #expect(night.first?.sceneID == "nightlight")
        let morning = log.scores(at: date(15, 7, 5), calendar: calendar)
        #expect(morning.first?.sceneID == "energize")
    }

    @Test func wrapsAroundMidnight() {
        var log = UsageLog()
        log.record(sceneID: "late", at: date(12, 23, 50))
        let scores = log.scores(at: date(13, 0, 20), calendar: calendar)
        #expect((scores.first?.score ?? 0) > 0.8)
    }

    @Test func oldHabitsFade() {
        var log = UsageLog()
        log.record(sceneID: "old", at: date(1, 20))
        log.record(sceneID: "new", at: date(14, 20))
        let popularity = log.popularity(at: date(15, 20))
        #expect((popularity["new"] ?? 0) > (popularity["old"] ?? 0))
    }

    @Test func ignoresImmediateRepeats() {
        var log = UsageLog()
        log.record(sceneID: "a", at: date(12, 20))
        log.record(sceneID: "a", at: date(12, 20).addingTimeInterval(5))
        #expect(log.uses.count == 1)
    }
}

// MARK: - Device health

@MainActor
@Suite struct DeviceHealthTests {
    @Test func reportsLowBatteryAndUnreachableDevices() throws {
        let store = HueStore()
        try store.load(HueStoreTests.fixture() + [
            ["id": "switch", "type": "device", "metadata": ["name": "Dimmer", "archetype": "unknown_archetype"], "services": []],
            ["id": "power", "type": "device_power", "owner": ["rid": "switch", "rtype": "device"],
             "power_state": ["battery_state": "low", "battery_level": 9]],
            ["id": "link", "type": "zigbee_connectivity", "owner": ["rid": "switch", "rtype": "device"], "status": "connectivity_issue"],
        ])
        let issues = store.deviceIssues.filter { $0.deviceID == "switch" }
        #expect(issues.contains { if case .battery(9, false) = $0.kind { true } else { false } })
        #expect(issues.contains { $0.kind == .unreachable })
    }

    @Test func healthyFixtureHasNoIssues() throws {
        let store = HueStore()
        try store.load(HueStoreTests.fixture())
        #expect(store.deviceIssues.isEmpty)
    }
}

// MARK: - Spoken names

@Suite struct SpokenNamesTests {
    let home: Set<String> = ["Zimmer", "Wohnzimmer", "Flur", "Wohnzimmer Lampe",
                             "Rundlampe", "Lightstrip", "Deckenlampe", "Stehlampe", "Lampen", "Vitrinen", "Lampe"]

    @Test func splitsEnglishCompoundsLikeSiriWritesThem() {
        #expect(SpokenNames.variants(of: "Lightstrip", avoiding: home) == ["Light Strip"])
        #expect(SpokenNames.variants(of: "Light Strip", avoiding: home).contains("Lightstrip") == false) // taken
    }

    @Test func offersTheSingularForPlurals() {
        #expect(SpokenNames.variants(of: "Vitrinen", avoiding: home) == ["Vitrine"])
    }

    @Test func neverCollidesWithAnotherDevice() {
        // "Lampen" → "Lampe" would hit the plug in the hallway.
        #expect(SpokenNames.variants(of: "Lampen", avoiding: home).isEmpty)
        #expect(SpokenNames.variants(of: "Deckenlampe", avoiding: home).isEmpty)
        #expect(SpokenNames.variants(of: "Zimmer", avoiding: home).isEmpty)
    }

    @Test func matchesHowPeopleSayNames() {
        let names = Array(home)
        #expect(SpokenNames.bestMatch(for: "Light Strip", in: names) { $0 } == "Lightstrip")
        #expect(SpokenNames.bestMatch(for: "vitrine", in: names) { $0 } == "Vitrinen")
        #expect(SpokenNames.bestMatch(for: "Lampe", in: names) { $0 } == "Lampe")
        #expect(SpokenNames.bestMatch(for: "Lampen", in: names) { $0 } == "Lampen")
        #expect(SpokenNames.bestMatch(for: "Küche", in: names) { $0 } == nil)
    }
}

// MARK: - Direct decoding

@Suite @MainActor struct JSONValueDecoderTests {
    /// The old path: through JSON text, with Foundation's decoder.
    func viaText<T: Decodable>(_ value: JSONValue, as type: T.Type) -> T? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func expectSame<T: Decodable & Equatable>(_ type: T.Type, in resources: [JSONValue]) {
        for resource in resources {
            let direct = try? resource.decode(type)
            #expect(direct == viaText(resource, as: type), "\(T.self) differs for \(resource["id"]?.stringValue ?? "?")")
        }
    }

    @Test func matchesFoundationForEveryResource() throws {
        let resources = try HueStoreTests.fixture() + PerformanceTests.largeHome(rooms: 3)
        expectSame(Light.self, in: resources)
        expectSame(GroupedLight.self, in: resources)
        expectSame(HueGroup.self, in: resources)
        expectSame(Device.self, in: resources)
        expectSame(HueScene.self, in: resources)
        expectSame(SmartScene.self, in: resources)
        expectSame(BridgeHome.self, in: resources)
        expectSame(BehaviorInstance.self, in: resources)
        expectSame(ZigbeeConnectivity.self, in: resources)
        expectSame(DeviceSoftwareUpdate.self, in: resources)
        expectSame(JSONValue.self, in: resources)
    }

    @Test func numbersAndNulls() throws {
        struct Sample: Decodable, Equatable {
            var int: Int
            var double: Double
            var optional: String?
            var nested: [Int]
        }
        let value: JSONValue = ["int": 4, "double": 4.5, "optional": .null, "nested": [1, 2]]
        #expect(try value.decode(Sample.self) == Sample(int: 4, double: 4.5, optional: nil, nested: [1, 2]))
        // Like JSONDecoder: a fractional number is no Int, a missing key is an error.
        #expect(throws: DecodingError.self) { try (["int": 4.5, "double": 1, "nested": []] as JSONValue).decode(Sample.self) }
        #expect(throws: DecodingError.self) { try (["double": 1, "nested": []] as JSONValue).decode(Sample.self) }
        #expect(throws: DecodingError.self) { try JSONValue.number(1).decode(Bool.self) }
    }
}

// MARK: - Credential file

@Suite struct CredentialFileTests {
    @Test func writesAtomicallyWithOwnerOnlyPermissions() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "hoku-cred-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "bridge.json")

        // An older file with loose permissions gets replaced by a 0600 one.
        try Data("old".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        try CredentialStore.writeRestricted(Data("new".utf8), to: file)

        #expect(try String(contentsOf: file, encoding: .utf8) == "new")
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
        // No temporary files left behind.
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["bridge.json"])
    }
}

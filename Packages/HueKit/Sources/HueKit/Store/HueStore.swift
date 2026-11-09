import Foundation
import Observation

/// Live mirror of one bridge.
///
/// Every resource is kept as raw JSON keyed by ID. Event-stream patches and our own
/// optimistic writes are deep-merged into it, then the affected typed model is
/// decoded again. Unknown fields and new resource types never break anything.
@MainActor
@Observable
public final class HueStore {
    public enum ConnectionState: Equatable, Sendable {
        case disconnected
        case connecting
        case live
        case offline(String)
        case unauthorized
    }

    public enum SceneRecall: String, Sendable {
        /// The scene's default: dynamic if it was saved that way.
        case active
        case dynamic = "dynamic_palette"
        case `static`
    }

    // MARK: Published state

    public internal(set) var connection: ConnectionState = .disconnected
    public internal(set) var credentials: BridgeCredentials?
    public private(set) var lastSync: Date?
    public private(set) var lastError: String?

    public private(set) var lights: [String: Light] = [:]
    public private(set) var groupedLights: [String: GroupedLight] = [:]
    public private(set) var rooms: [String: HueGroup] = [:]
    public private(set) var zones: [String: HueGroup] = [:]
    public private(set) var devices: [String: Device] = [:]
    public private(set) var scenes: [String: HueScene] = [:]
    public private(set) var smartScenes: [String: SmartScene] = [:]
    public private(set) var bridgeHome: BridgeHome?
    public private(set) var behaviorScripts: [String: BehaviorScript] = [:]
    public private(set) var behaviorInstances: [String: BehaviorInstance] = [:]
    public private(set) var devicePower: [String: DevicePower] = [:]
    public private(set) var connectivity: [String: ZigbeeConnectivity] = [:]
    public private(set) var softwareUpdates: [String: DeviceSoftwareUpdate] = [:]
    /// Running sleep timers, keyed by room/zone ID.
    public internal(set) var fadeOuts: [String: FadeOut] = [:]

    // MARK: Internals

    public let client: HueClient
    @ObservationIgnored var raw: [String: JSONValue] = [:]
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var suppressed: [String: (keys: Set<String>, until: Date)] = [:]
    @ObservationIgnored private var reconcileTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var throttle: CommandThrottle!

    @ObservationIgnored private var resyncTask: Task<Void, Never>?

    /// Called whenever a scene becomes active: recalled here, or elsewhere (Hue app,
    /// switches) as reported by the event stream. Feeds the usage learning.
    @ObservationIgnored public var onSceneActivated: ((HueScene) -> Void)?

    /// Former names, so commands made before a rename in the Hue app still find their target.
    @ObservationIgnored public var nameHistory = NameHistory()

    /// How long our own writes win over (lagging) event-stream values.
    private static let suppressionWindow: TimeInterval = 2.0

    public init(client: HueClient = HueClient()) {
        self.client = client
        throttle = CommandThrottle { [weak self] target, body in
            await self?.send(body, to: target)
        }
    }

    // MARK: Connection

    public func connect(_ credentials: BridgeCredentials) {
        disconnect()
        self.credentials = credentials
        connection = .connecting
        Task { await refresh() }

        let stream = client.eventStream(credentials)
        streamTask = Task { [weak self] in
            var hasConnectedBefore = false
            for await message in stream {
                guard let self else { return }
                switch message {
                case .connected:
                    connection = .live
                    // Anything could have happened while we were away — and if the first
                    // load failed (e.g. no local network permission yet), load now.
                    if hasConnectedBefore || lastSync == nil { await refresh() }
                    hasConnectedBefore = true
                case let .events(events):
                    apply(events)
                case let .disconnected(reason):
                    if connection != .unauthorized { connection = .offline(reason) }
                case .unauthorized:
                    connection = .unauthorized
                }
            }
        }
    }

    public func disconnect() {
        streamTask?.cancel()
        streamTask = nil
        resyncTask?.cancel()
        resyncTask = nil
        connection = .disconnected
    }

    /// Restart after sleep/wake or network changes; the old stream is likely dead.
    public func reconnect() {
        guard let credentials else { return }
        connect(credentials)
    }

    public func forget() {
        disconnect()
        credentials = nil
        raw = [:]
        rebuildAll()
    }

    /// Full state load. Cheap enough (one request) to call whenever in doubt.
    public func refresh() async {
        guard let credentials else { return }
        do {
            load(try await client.allResources(credentials))
            if connection != .live { connection = .live }
        } catch HueError.unauthorized {
            connection = .unauthorized
        } catch {
            connection = .offline(error.localizedDescription)
        }
    }

    /// Replaces the whole state with `resources` (from `GET /clip/v2/resource`).
    func load(_ resources: [JSONValue]) {
        var fresh: [String: JSONValue] = [:]
        for resource in resources {
            if let id = resource["id"]?.stringValue { fresh[id] = resource }
        }
        raw = fresh
        rebuildAll()
        lastSync = .now
    }

    /// Called when the popover opens: resync if the event stream has been quiet a while.
    public func refreshIfStale(olderThan interval: TimeInterval = 30) {
        guard let lastSync, Date.now.timeIntervalSince(lastSync) > interval else { return }
        Task { await refresh() }
    }

    public func dismissError() {
        lastError = nil
    }

    public func reportError(_ message: String) {
        lastError = message
    }

    // MARK: Event stream

    func apply(_ events: [HueEvent]) {
        let now = Date.now
        var needsResync = false
        for event in events {
            for resource in event.data {
                guard let id = resource["id"]?.stringValue else { continue }
                switch event.type {
                case .add:
                    raw[id] = resource
                    needsResync = true
                case .update:
                    guard let existing = raw[id] else {
                        // Something we never heard of: we must have missed its "add".
                        needsResync = true
                        continue
                    }
                    let wasActive = scenes[id]?.isActive ?? false
                    raw[id] = existing.merging(stripSuppressedKeys(from: resource, id: id, now: now))
                    if !wasActive, resource["type"]?.stringValue == "scene" {
                        rebuild(id, type: "scene")
                        if let scene = scenes[id], scene.isActive { onSceneActivated?(scene) }
                    }
                case .delete:
                    raw[id] = nil
                    needsResync = true
                case .error, .unknown:
                    continue
                }
                rebuild(id, type: resource["type"]?.stringValue)
            }
        }
        lastSync = now
        if needsResync { scheduleResync() }
    }

    /// True while a full reload is scheduled after structural changes.
    var isResyncPending: Bool { resyncTask != nil }

    /// Lamps, rooms or scenes were added or removed (e.g. in the Hue app). Events carry
    /// the new resource, but a room's new member or a device's services may arrive in
    /// separate events, in any order — so once things settle, reload everything once.
    private func scheduleResync() {
        resyncTask?.cancel()
        resyncTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let self else { return }
            resyncTask = nil
            await refresh()
        }
    }

    private func stripSuppressedKeys(from resource: JSONValue, id: String, now: Date) -> JSONValue {
        guard let entry = suppressed[id], case var .object(object) = resource else { return resource }
        guard entry.until > now else {
            suppressed[id] = nil
            return resource
        }
        for key in entry.keys { object[key] = nil }
        return .object(object)
    }

    // MARK: Typed views

    // Typed models are only reassigned when they actually changed: views observe whole
    // dictionaries, and the bridge repeats unchanged values (grouped lights echo every
    // lamp change, refreshes return the same state). Skipping those saves redraws.

    private func rebuildAll() {
        let byType = Dictionary(grouping: raw) { $0.value["type"]?.stringValue ?? "" }
        func decoded<T: Decodable>(_ type: String, as _: T.Type) -> [String: T] {
            var result: [String: T] = [:]
            for (id, value) in byType[type] ?? [] {
                if let item = try? value.decode(T.self) { result[id] = item }
            }
            return result
        }
        replace(\.lights, with: decoded("light", as: Light.self))
        replace(\.groupedLights, with: decoded("grouped_light", as: GroupedLight.self))
        replace(\.rooms, with: decoded("room", as: HueGroup.self))
        replace(\.zones, with: decoded("zone", as: HueGroup.self))
        replace(\.devices, with: decoded("device", as: Device.self))
        replace(\.scenes, with: decoded("scene", as: HueScene.self))
        replace(\.smartScenes, with: decoded("smart_scene", as: SmartScene.self))
        replace(\.bridgeHome, with: decoded("bridge_home", as: BridgeHome.self).values.first)
        replace(\.behaviorScripts, with: decoded("behavior_script", as: BehaviorScript.self))
        replace(\.behaviorInstances, with: decoded("behavior_instance", as: BehaviorInstance.self))
        replace(\.devicePower, with: decoded("device_power", as: DevicePower.self))
        replace(\.connectivity, with: decoded("zigbee_connectivity", as: ZigbeeConnectivity.self))
        replace(\.softwareUpdates, with: decoded("device_software_update", as: DeviceSoftwareUpdate.self))
    }

    func rebuild(_ id: String, type: String?) {
        let value = raw[id]
        switch type ?? value?["type"]?.stringValue {
        case "light": assign(\.lights, id, value)
        case "grouped_light": assign(\.groupedLights, id, value)
        case "room": assign(\.rooms, id, value)
        case "zone": assign(\.zones, id, value)
        case "device": assign(\.devices, id, value)
        case "scene": assign(\.scenes, id, value)
        case "smart_scene": assign(\.smartScenes, id, value)
        case "bridge_home": replace(\.bridgeHome, with: value.flatMap { try? $0.decode(BridgeHome.self) })
        case "behavior_script": assign(\.behaviorScripts, id, value)
        case "behavior_instance": assign(\.behaviorInstances, id, value)
        case "device_power": assign(\.devicePower, id, value)
        case "zigbee_connectivity": assign(\.connectivity, id, value)
        case "device_software_update": assign(\.softwareUpdates, id, value)
        default: break
        }
    }

    private func assign<T: Decodable & Equatable>(_ keyPath: ReferenceWritableKeyPath<HueStore, [String: T]>, _ id: String, _ value: JSONValue?) {
        let decoded = value.flatMap { try? $0.decode(T.self) }
        if self[keyPath: keyPath][id] != decoded {
            self[keyPath: keyPath][id] = decoded
        }
    }

    private func replace<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<HueStore, T>, with value: T) {
        if self[keyPath: keyPath] != value {
            self[keyPath: keyPath] = value
        }
    }

    // MARK: Derived data

    /// Pinned and hand-sorted rooms and zones; by name unless the user changed it.
    public var groupOrder = GroupOrder()

    public var sortedRooms: [HueGroup] {
        groupOrder.sorted(Array(rooms.values))
    }

    public var sortedZones: [HueGroup] {
        groupOrder.sorted(Array(zones.values))
    }

    public func group(_ id: String) -> HueGroup? {
        rooms[id] ?? zones[id]
    }

    public func groupedLight(for group: HueGroup) -> GroupedLight? {
        group.groupedLightID.flatMap { groupedLights[$0] }
    }

    public func lights(in group: HueGroup) -> [Light] {
        var ids: [String] = []
        for child in group.children ?? [] {
            switch child.rtype {
            case "device": ids += devices[child.rid]?.lightIDs ?? []
            case "light": ids.append(child.rid)
            default: break
            }
        }
        return ids.compactMap { lights[$0] }
            .sorted { name(of: $0).localizedStandardCompare(name(of: $1)) == .orderedAscending }
    }

    public func scenes(in group: HueGroup) -> [HueScene] {
        scenes.values
            .filter { $0.group?.rid == group.id }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func smartScenes(in group: HueGroup) -> [SmartScene] {
        smartScenes.values
            .filter { $0.group?.rid == group.id }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The room that contains every light of `zone`, if there is one. Such zones are
    /// shown inside their room instead of as a separate top-level entry.
    public func parentRoom(of zone: HueGroup) -> HueGroup? {
        let zoneLights = Set(lights(in: zone).map(\.id))
        guard zone.isZone, !zoneLights.isEmpty else { return nil }
        return sortedRooms.first { Set(lights(in: $0).map(\.id)).isSuperset(of: zoneLights) }
    }

    /// Zones spanning several rooms, shown on the home page.
    public var topLevelZones: [HueGroup] {
        sortedZones.filter { parentRoom(of: $0) == nil }
    }

    public func zones(in room: HueGroup) -> [HueGroup] {
        sortedZones.filter { parentRoom(of: $0)?.id == room.id }
    }

    public func activeScene(in group: HueGroup) -> HueScene? {
        scenes(in: group).first { $0.isActive }
    }

    /// Device names are the user-facing ones; `light.metadata` is deprecated.
    public func name(of light: Light) -> String {
        light.owner.flatMap { devices[$0.rid]?.metadata?.name } ?? light.metadata?.name ?? String(localized: "Lampe", bundle: .hueKit)
    }

    public func archetype(of light: Light) -> String? {
        light.owner.flatMap { devices[$0.rid]?.metadata?.archetype } ?? light.metadata?.archetype
    }

    public var anyLightOn: Bool {
        lights.values.contains { $0.isOn }
    }

    public var lightsOnCount: Int {
        lights.values.filter(\.isOn).count
    }

    // MARK: Lookup by name (URL scheme, later App Intents)

    /// Name lookups tolerate how people and Siri say names: spacing ("Light Strip"),
    /// accents, case and singular/plural ("Vitrine" for "Vitrinen").
    /// Names renamed in the Hue app still resolve, as long as nothing else took them over.
    public func findGroup(named name: String) -> HueGroup? {
        let groups = sortedRooms + sortedZones
        return SpokenNames.bestMatch(for: name, in: groups) { $0.name }
            ?? nameHistory.match(name, in: groups)
    }

    public func findLight(named name: String) -> Light? {
        let candidates = Array(lights.values)
        return SpokenNames.bestMatch(for: name, in: candidates) { self.name(of: $0) }
            ?? nameHistory.match(name, in: candidates)
    }

    /// Without a room, many rooms may have a scene of that name ("Entspannen"): prefer a
    /// room that is on (that's usually the one meant), then rooms in alphabetical order.
    public func findScene(named name: String, in group: HueGroup? = nil) -> HueScene? {
        let candidates = group.map { scenes(in: $0) } ?? scenesByLikelyRoom
        return SpokenNames.bestMatch(for: name, in: candidates) { $0.name }
            ?? nameHistory.match(name, in: candidates)
    }

    private var scenesByLikelyRoom: [HueScene] {
        let rank: [String: (Int, String)] = Dictionary(uniqueKeysWithValues: (sortedRooms + sortedZones).map { group in
            (group.id, (groupedLight(for: group)?.isOn == true ? 0 : 1, group.name))
        })
        return scenes.values.sorted { lhs, rhs in
            let left = rank[lhs.group?.rid ?? ""] ?? (2, "")
            let right = rank[rhs.group?.rid ?? ""] ?? (2, "")
            if left.0 != right.0 { return left.0 < right.0 }
            if left.1 != right.1 { return left.1.localizedStandardCompare(right.1) == .orderedAscending }
            return lhs.id < rhs.id
        }
    }

    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) == .orderedSame
    }

    // MARK: Commands — groups

    public func setOn(_ on: Bool, group: HueGroup) {
        guard let id = group.groupedLightID else { return }
        write(type: "grouped_light", id: id, body: ["on": ["on": .bool(on)]])
        // The bridge will report member lights shortly; reflect the toggle right away.
        for light in lights(in: group) {
            patchLocally(light.id, ["on": ["on": .bool(on)]])
        }
    }

    public func setBrightness(_ brightness: Double, group: HueGroup) {
        guard let id = group.groupedLightID else { return }
        var body: JSONValue = ["dimming": ["brightness": .number(Self.clampBrightness(brightness))]]
        if groupedLights[id]?.isOn == false {
            body = body.merging(["on": ["on": true]])
        }
        write(type: "grouped_light", id: id, body: body)
    }

    /// Relative dimming for gestures and keys. Dimming down never switches a room on.
    public func adjustBrightness(by delta: Double, group: HueGroup) {
        let groupedLight = groupedLight(for: group)
        let isOn = groupedLight?.isOn == true
        guard isOn || delta > 0 else { return }
        setBrightness((isOn ? groupedLight?.dimming?.brightness ?? 0 : 0) + delta, group: group)
    }

    /// "Alles aus" that waits for the bridge's answer, for callers that confirm the
    /// result to the user (the away reminder's notification).
    public func switchEverythingOff() async throws {
        guard let credentials, let id = bridgeHome?.groupedLightID else {
            throw HueError.bridge(String(localized: "Keine Lichtgruppe für das ganze Zuhause gefunden.", bundle: .hueKit))
        }
        try await client.update(credentials, type: "grouped_light", id: id, body: ["on": ["on": false]])
        for light in lights.values where light.isOn {
            patchLocally(light.id, ["on": ["on": false]])
        }
        for group in Array(rooms.values) + Array(zones.values) {
            if let groupedID = group.groupedLightID {
                patchLocally(groupedID, ["on": ["on": false]])
            }
        }
    }

    public func setAllOff() {
        guard let id = bridgeHome?.groupedLightID else { return }
        write(type: "grouped_light", id: id, body: ["on": ["on": false]])
        for light in lights.values where light.isOn {
            patchLocally(light.id, ["on": ["on": false]])
        }
        for group in Array(rooms.values) + Array(zones.values) {
            if let groupedID = group.groupedLightID {
                patchLocally(groupedID, ["on": ["on": false]])
            }
        }
    }

    // MARK: Commands — lights

    public func setOn(_ on: Bool, light: Light) {
        write(type: "light", id: light.id, body: ["on": ["on": .bool(on)]])
        holdGroups(containing: light.id)
    }

    public func setBrightness(_ brightness: Double, light: Light) {
        var body: JSONValue = ["dimming": ["brightness": .number(Self.clampBrightness(brightness))]]
        if !light.isOn { body = body.merging(["on": ["on": true]]) }
        write(type: "light", id: light.id, body: body)
        if !light.isOn { holdGroups(containing: light.id) }
    }

    /// A room is on exactly when one of its lamps is. After switching a single lamp, show
    /// that at once, and hold it for a moment: while the lamp fades, the bridge reports
    /// in-between states for the room (off, on again, off), which made the card blink.
    /// The same goes for the room's brightness: the bridge reports it about a second late,
    /// so switching off and quickly on again let the "0 %" of the off land after the on.
    /// The real state is read back once the moment has passed.
    func holdGroups(containing lightID: String) {
        for group in Array(rooms.values) + Array(zones.values) {
            let members = lights(in: group)
            guard let groupedID = group.groupedLightID, members.contains(where: { $0.id == lightID }) else { continue }
            let lit = members.filter(\.isOn)
            var patch: JSONValue = ["on": ["on": .bool(!lit.isEmpty)]]
            var held: Set<String> = ["on"]
            if groupedLights[groupedID]?.dimming != nil {
                // Like the bridge: the average of the lit lamps that can dim, else 0.
                let dimmable = lit.filter(\.supportsDimming)
                let average = dimmable.isEmpty ? 0 : dimmable.map(\.brightness).reduce(0, +) / Double(dimmable.count)
                patch = patch.merging(["dimming": ["brightness": .number(average)]])
                held.insert("dimming")
            }
            patchLocally(groupedID, patch)
            let keys = (suppressed[groupedID]?.keys ?? []).union(held)
            suppressed[groupedID] = (keys, Date.now.addingTimeInterval(Self.suppressionWindow))
            scheduleReconcile(type: "grouped_light", id: groupedID)
        }
    }

    /// Relative dimming for gestures and keys. Dimming down never switches a lamp on.
    public func adjustBrightness(by delta: Double, light: Light) {
        guard light.supportsDimming, light.isOn || delta > 0 else { return }
        setBrightness((light.isOn ? light.brightness : 0) + delta, light: light)
    }

    public func setColor(_ rgb: RGB, light: Light) {
        let xy = ColorMath.xy(from: rgb, gamut: light.color?.gamut)
        var body: JSONValue = ["color": ["xy": ["x": .number(xy.x), "y": .number(xy.y)]]]
        if !light.isOn { body = body.merging(["on": ["on": true]]) }
        write(
            type: "light", id: light.id, body: body,
            // Locally, also leave color-temperature mode so the UI switches over.
            localPatch: body.merging(["color_temperature": ["mirek_valid": false]])
        )
        if !light.isOn { holdGroups(containing: light.id) }
    }

    public func setColorTemperature(mirek: Int, light: Light) {
        let schema = light.colorTemperature?.mirekSchema
        let clamped = min(max(mirek, schema?.mirekMinimum ?? 153), schema?.mirekMaximum ?? 500)
        var body: JSONValue = ["color_temperature": ["mirek": .number(Double(clamped))]]
        if !light.isOn { body = body.merging(["on": ["on": true]]) }
        write(
            type: "light", id: light.id, body: body,
            localPatch: body.merging(["color_temperature": ["mirek_valid": true]])
        )
        if !light.isOn { holdGroups(containing: light.id) }
    }

    // MARK: Commands — scenes

    public func recall(_ scene: HueScene, as mode: SceneRecall = .active) {
        write(type: "scene", id: scene.id, body: ["recall": ["action": .string(mode.rawValue)]], suppress: false)
        onSceneActivated?(scene)

        // Mark this scene active and its siblings inactive until the bridge confirms.
        let status: String = switch mode {
        case .dynamic: "dynamic_palette"
        case .static: "static"
        case .active: scene.supportsDynamic && scene.autoDynamic == true ? "dynamic_palette" : "static"
        }
        if let groupID = scene.group?.rid, let group = group(groupID) {
            for sibling in scenes(in: group) where sibling.isActive && sibling.id != scene.id {
                patchLocally(sibling.id, ["status": ["active": "inactive"]])
            }
            if let groupedID = group.groupedLightID {
                patchLocally(groupedID, ["on": ["on": true]])
            }
        }
        patchLocally(scene.id, ["status": ["active": .string(status)]])
    }

    public func setSpeed(_ speed: Double, scene: HueScene) {
        write(type: "scene", id: scene.id, body: ["speed": .number(min(max(speed, 0), 1))])
    }

    public func activate(_ smartScene: SmartScene) {
        write(type: "smart_scene", id: smartScene.id, body: ["recall": ["action": "activate"]], suppress: false)
    }

    // MARK: Write pipeline

    private static func clampBrightness(_ value: Double) -> Double {
        min(max(value.rounded(), 1), 100)
    }

    func write(type: String, id: String, body: JSONValue, localPatch: JSONValue? = nil, suppress: Bool = true) {
        patchLocally(id, localPatch ?? body)

        if suppress, case let .object(object) = body {
            let keys = Set(object.keys).subtracting(["dynamics", "recall"])
            let previous = suppressed[id]?.keys ?? []
            suppressed[id] = (previous.union(keys), Date.now.addingTimeInterval(Self.suppressionWindow))
            scheduleReconcile(type: type, id: id)
        }

        let target = CommandThrottle.Target(type: type, id: id)
        Task { await throttle.submit(body, to: target) }
    }

    func patchLocally(_ id: String, _ patch: JSONValue) {
        guard let existing = raw[id] else { return }
        raw[id] = existing.merging(patch)
        rebuild(id, type: nil)
    }

    /// After the suppression window, fetch the real state once, in case we dropped
    /// an event that disagreed with our optimistic value (e.g. the bridge clamped it).
    private func scheduleReconcile(type: String, id: String) {
        reconcileTasks[id]?.cancel()
        reconcileTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.suppressionWindow + 0.5))
            guard !Task.isCancelled, let self, let credentials else { return }
            self.reconcileTasks[id] = nil
            self.suppressed[id] = nil
            if let fresh = try? await client.resource(credentials, type: type, id: id) {
                raw[id] = fresh
                rebuild(id, type: type)
            }
        }
    }

    private func send(_ body: JSONValue, to target: CommandThrottle.Target) async {
        guard let credentials else { return }
        do {
            try await client.update(credentials, type: target.type, id: target.id, body: body)
        } catch HueError.unauthorized {
            connection = .unauthorized
        } catch {
            lastError = error.localizedDescription
        }
    }
}

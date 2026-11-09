import Foundation

/// Bridge-side automations created by the Hue app. They run on the bridge, so they
/// fire even while the Mac sleeps.
public enum RoutineKind: Sendable, CaseIterable {
    case wakeUp
    case goToSleep

    var scriptName: String {
        switch self {
        case .wakeUp: "Basic wake up routine"
        case .goToSleep: "Go to sleep routines"
        }
    }
}

public struct RoutineDraft: Sendable, Equatable {
    public var name: String
    public var hour: Int
    public var minute: Int
    /// Lower-case English weekday names as the bridge expects ("monday" …).
    public var weekdays: [String]
    public var groupID: String
    public var fadeMinutes: Int
    /// Wake-up only: brightness at the end of the sunrise.
    public var endBrightness: Double

    public init(name: String, hour: Int, minute: Int, weekdays: [String], groupID: String, fadeMinutes: Int, endBrightness: Double) {
        self.name = name
        self.hour = hour
        self.minute = minute
        self.weekdays = weekdays
        self.groupID = groupID
        self.fadeMinutes = fadeMinutes
        self.endBrightness = endBrightness
    }

    public static let weekdayOrder = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
}

/// A sleep timer: dimmable lights fade out on the bridge itself, plugs are switched
/// off by the app when the timer ends.
public struct FadeOut: Sendable, Equatable {
    public var ends: Date
    public var restoreBrightness: Double
    public var plugIDs: [String]
}

extension HueStore {
    // MARK: Routines

    public func routines(_ kind: RoutineKind) -> [BehaviorInstance] {
        guard let script = behaviorScripts.values.first(where: { $0.name == kind.scriptName }) else { return [] }
        return behaviorInstances.values
            .filter { $0.scriptID == script.id }
            .sorted { ($0.hour ?? 0, $0.minute ?? 0, $0.name) < ($1.hour ?? 0, $1.minute ?? 0, $1.name) }
    }

    public func kind(of routine: BehaviorInstance) -> RoutineKind? {
        guard let script = behaviorScripts[routine.scriptID] else { return nil }
        return RoutineKind.allCases.first { $0.scriptName == script.name }
    }

    public func setEnabled(_ enabled: Bool, routine: BehaviorInstance) {
        write(type: "behavior_instance", id: routine.id, body: ["enabled": .bool(enabled)], suppress: false)
    }

    public func draft(from routine: BehaviorInstance) -> RoutineDraft {
        RoutineDraft(
            name: routine.name,
            hour: routine.hour ?? 7,
            minute: routine.minute ?? 0,
            weekdays: routine.weekdays,
            groupID: routine.groupIDs.first ?? sortedRooms.first?.id ?? "",
            fadeMinutes: max((routine.fadeSeconds ?? 900) / 60, 1),
            endBrightness: routine.configuration?.endBrightness ?? 100
        )
    }

    /// Saves `draft` into an existing routine, keeping configuration fields we don't edit.
    public func save(_ draft: RoutineDraft, to routine: BehaviorInstance) async throws {
        guard let credentials, let kind = kind(of: routine) else { return }
        let existing = raw[routine.id]?["configuration"] ?? [:]
        let configuration = existing.merging(try configuration(for: draft, kind: kind))
        try await client.update(
            credentials, type: "behavior_instance", id: routine.id,
            body: ["configuration": configuration, "metadata": ["name": .string(draft.name)]]
        )
        await reload(type: "behavior_instance", id: routine.id)
    }

    public func create(_ draft: RoutineDraft, kind: RoutineKind) async throws {
        guard let credentials,
              let script = behaviorScripts.values.first(where: { $0.name == kind.scriptName })
        else { throw HueError.bridge(String(localized: "Die Bridge bietet diese Automation nicht an.", bundle: .hueKit)) }
        let body: JSONValue = [
            "type": "behavior_instance",
            "script_id": .string(script.id),
            "enabled": true,
            "metadata": ["name": .string(draft.name)],
            "configuration": try configuration(for: draft, kind: kind),
        ]
        if let id = try await client.create(credentials, type: "behavior_instance", body: body) {
            await reload(type: "behavior_instance", id: id)
        }
    }

    public func delete(_ routine: BehaviorInstance) async throws {
        guard let credentials else { return }
        try await client.delete(credentials, type: "behavior_instance", id: routine.id)
        raw[routine.id] = nil
        rebuild(routine.id, type: "behavior_instance")
    }

    private func configuration(for draft: RoutineDraft, kind: RoutineKind) throws -> JSONValue {
        guard let group = group(draft.groupID) else { throw HueError.bridge(String(localized: "Bitte einen Raum wählen.", bundle: .hueKit)) }
        // The Hue app lists the dimmable lights explicitly; plugs can't fade.
        let items: [JSONValue] = lights(in: group).filter(\.supportsDimming).map {
            ["rid": .string($0.id), "rtype": "light"]
        }
        var configuration: JSONValue = [
            "when": [
                "recurrence_days": .array(draft.weekdays.map { .string($0) }),
                "time_point": ["type": "time", "time": ["hour": .number(Double(draft.hour)), "minute": .number(Double(draft.minute))]],
            ],
            "where": [["group": ["rid": .string(group.id), "rtype": .string(group.type)], "items": .array(items)]],
        ]
        let fade: JSONValue = ["seconds": .number(Double(draft.fadeMinutes * 60))]
        switch kind {
        case .wakeUp:
            configuration = configuration.merging([
                "style": "sunrise",
                "fade_in_duration": fade,
                "end_brightness": .number(min(max(draft.endBrightness, 1), 100)),
            ])
        case .goToSleep:
            configuration = configuration.merging([
                "style": "sunset",
                "fade_out_duration": fade,
                "end_state": "turn_off",
            ])
        }
        return configuration
    }

    func reload(type: String, id: String) async {
        guard let credentials, let fresh = try? await client.resource(credentials, type: type, id: id) else { return }
        raw[id] = fresh
        rebuild(id, type: type)
    }

    // MARK: Sleep timer

    /// Fades a room out over `minutes` (max. 100, the bridge's transition limit).
    public func startFadeOut(_ group: HueGroup, minutes: Int) {
        let duration = min(max(minutes, 1), 100) * 60_000
        let members = lights(in: group).filter(\.isOn)
        let dimmable = members.filter(\.supportsDimming)
        let plugs = members.filter { !$0.supportsDimming }.map(\.id)
        let restore = groupedLight(for: group)?.dimming?.brightness ?? 100

        // Individual light commands, so plugs in the room aren't switched off right away.
        for light in dimmable {
            write(
                type: "light", id: light.id,
                body: ["on": ["on": false], "dynamics": ["duration": .number(Double(duration))]],
                localPatch: [:], suppress: false
            )
        }
        let ends = Date.now.addingTimeInterval(Double(duration) / 1000)
        fadeOuts[group.id] = FadeOut(ends: ends, restoreBrightness: restore, plugIDs: plugs)

        Task { [weak self] in
            try? await Task.sleep(until: .now + .milliseconds(duration), clock: .continuous)
            self?.finishFadeOutIfDue(group.id)
        }
    }

    public func cancelFadeOut(_ group: HueGroup) {
        guard let fadeOut = fadeOuts.removeValue(forKey: group.id) else { return }
        for light in lights(in: group) where light.supportsDimming && !fadeOut.plugIDs.contains(light.id) {
            write(type: "light", id: light.id, body: [
                "on": ["on": true],
                "dimming": ["brightness": .number(fadeOut.restoreBrightness)],
                "dynamics": ["duration": 400],
            ])
        }
    }

    /// Ends timers that expired, e.g. while the Mac was asleep. Call after waking up.
    public func finishExpiredFadeOuts() {
        for id in fadeOuts.keys { finishFadeOutIfDue(id) }
    }

    private func finishFadeOutIfDue(_ groupID: String) {
        guard let fadeOut = fadeOuts[groupID], fadeOut.ends <= .now else { return }
        fadeOuts[groupID] = nil
        for id in fadeOut.plugIDs {
            write(type: "light", id: id, body: ["on": ["on": false]])
        }
    }

    // MARK: Snapshots for Mac automations

    public func lightIDsOn(in groups: [HueGroup]) -> [String] {
        groups.flatMap { lights(in: $0) }.filter(\.isOn).map(\.id)
    }

    public func turnOn(lightIDs: [String]) {
        // Lamps removed in the meantime (e.g. in the Hue app) are skipped, not errors.
        for id in lightIDs where lights[id] != nil {
            write(type: "light", id: id, body: ["on": ["on": true]])
            holdGroups(containing: id)
        }
    }
}

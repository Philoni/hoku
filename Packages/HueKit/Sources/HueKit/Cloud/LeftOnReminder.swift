import Foundation

/// Which lights are still on at home, read from a set of resources (local or cloud).
public struct LeftOnReport: Equatable, Sendable {
    /// Rooms with at least one light on, in the Hue app's order.
    public var rooms: [String]
    public var lightIDs: Set<String>
    /// The "whole home" group, for switching everything off in one call.
    public var homeGroupedLightID: String?

    public init(rooms: [String], lightIDs: Set<String>, homeGroupedLightID: String? = nil) {
        self.rooms = rooms
        self.lightIDs = lightIDs
        self.homeGroupedLightID = homeGroupedLightID
    }

    public var isEmpty: Bool { lightIDs.isEmpty }

    @MainActor
    public static func from(resources: [JSONValue]) -> LeftOnReport {
        from(home(resources))
    }

    /// A throwaway store holding a full resource list, e.g. one fetched through the cloud.
    @MainActor
    public static func home(_ resources: [JSONValue]) -> HueStore {
        let store = HueStore()
        store.load(resources)
        return store
    }

    @MainActor
    public static func from(_ store: HueStore) -> LeftOnReport {
        let lit = store.lights.values.filter(\.isOn)
        let rooms = store.sortedRooms.filter { room in store.lights(in: room).contains(where: \.isOn) }
        return LeftOnReport(
            rooms: rooms.map(\.name),
            lightIDs: Set(lit.map(\.id)),
            homeGroupedLightID: store.bridgeHome?.groupedLightID
        )
    }

    /// The notification's text: where, then how much. Room names stand as a plain
    /// list (no "im"/"in der": German articles differ per room name), at most three.
    ///
    /// "Wohnzimmer · 2 Lampen an" / "Küche und Bad · 3 Lampen an" /
    /// "Wohnzimmer, Küche und 2 weitere Räume · 9 Lampen an"
    public var message: String {
        let lamps = lightIDs.count == 1 ? String(localized: "1 Lampe an", bundle: .hueKit) : String(localized: "\(lightIDs.count) Lampen an", bundle: .hueKit)
        let places: String? = switch rooms.count {
        case 0: nil
        case 1: rooms[0]
        case 2, 3: String(localized: "\(rooms.dropLast().joined(separator: ", ")) und \(rooms.last!)", bundle: .hueKit)
        default: String(localized: "\(rooms[0]), \(rooms[1]) und \(rooms.count - 2) weitere Räume", bundle: .hueKit)
        }
        return places.map { "\($0) · \(lamps)" } ?? lamps
    }
}

/// When to look and when to speak up, while the Mac is away from home.
///
/// One reminder per trip: Hoku says it once, and again only if different lights are on
/// than last time (someone at home, or a schedule, switched more on). Being home
/// again starts a new trip. While the Mac stays awake away from home, it looks at
/// most every half hour — the cloud has rate limits and a reminder every few
/// minutes would be nagging.
public struct LeftOnPolicy: Equatable, Sendable {
    public static let recheckInterval: TimeInterval = 30 * 60

    public private(set) var lastCheck: Date?
    public private(set) var remindedLights: Set<String>?

    public init() {}

    public enum Trigger: Sendable {
        /// Woke up, unlocked, joined a network: always worth a look.
        case arrival
        /// The periodic timer.
        case timer
    }

    public mutating func cameHome() {
        lastCheck = nil
        remindedLights = nil
    }

    /// The notification could not be shown: forget it, so the next check tries again.
    public mutating func reminderFailed() {
        remindedLights = nil
    }

    public func shouldCheck(_ trigger: Trigger, at now: Date) -> Bool {
        guard let lastCheck else { return true }
        switch trigger {
        case .arrival: return now.timeIntervalSince(lastCheck) > 60
        case .timer: return now.timeIntervalSince(lastCheck) >= Self.recheckInterval - 5
        }
    }

    /// Records a check; true if this report deserves a notification.
    public mutating func record(_ report: LeftOnReport, at now: Date) -> Bool {
        lastCheck = now
        guard !report.isEmpty else {
            // All off (by the phone's geofence, or by hand): forget, so lights that
            // come on later are reported again.
            remindedLights = nil
            return false
        }
        guard report.lightIDs != remindedLights else { return false }
        remindedLights = report.lightIDs
        return true
    }
}

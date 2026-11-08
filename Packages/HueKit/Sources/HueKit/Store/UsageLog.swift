import Foundation

/// Remembers when scenes get activated (from Hoku, the Hue app or a switch) and
/// scores them for a given moment: same time of day counts most, same kind of day
/// (weekday/weekend) a bit, and old habits fade with a three-week half-life.
public struct UsageLog: Codable, Sendable {
    public struct Use: Codable, Sendable, Hashable {
        public var sceneID: String
        public var date: Date
    }

    public private(set) var uses: [Use] = []
    static let capacity = 600

    public init(uses: [Use] = []) {
        self.uses = uses
    }

    public mutating func record(sceneID: String, at date: Date = .now) {
        // Ignore immediate repeats (double clicks, our own echo from the event stream).
        if let last = uses.last, last.sceneID == sceneID, date.timeIntervalSince(last.date) < 60 { return }
        uses.append(Use(sceneID: sceneID, date: date))
        if uses.count > Self.capacity { uses.removeFirst(uses.count - Self.capacity) }
    }

    /// Scores for `now`, highest first. Only scenes with at least one use appear.
    public func scores(at now: Date = .now, calendar: Calendar = .current) -> [(sceneID: String, score: Double)] {
        let nowHour = Self.hourOfDay(now, calendar)
        let nowIsWeekend = calendar.isDateInWeekend(now)
        var totals: [String: Double] = [:]
        for use in uses {
            let distance = Self.circularDistance(nowHour, Self.hourOfDay(use.date, calendar))
            let timeWeight = exp(-(distance * distance) / (2 * 1.25 * 1.25))
            let dayWeight = calendar.isDateInWeekend(use.date) == nowIsWeekend ? 1.2 : 0.7
            let ageDays = max(now.timeIntervalSince(use.date), 0) / 86_400
            let recency = pow(0.5, ageDays / 21)
            totals[use.sceneID, default: 0] += timeWeight * dayWeight * recency
        }
        return totals.map { ($0.key, $0.value) }.sorted { $0.score > $1.score }
    }

    /// How much a scene is used overall (time of day ignored), for ordering favorites.
    public func popularity(at now: Date = .now) -> [String: Double] {
        var totals: [String: Double] = [:]
        for use in uses {
            let ageDays = max(now.timeIntervalSince(use.date), 0) / 86_400
            totals[use.sceneID, default: 0] += pow(0.5, ageDays / 21)
        }
        return totals
    }

    static func hourOfDay(_ date: Date, _ calendar: Calendar) -> Double {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
    }

    static func circularDistance(_ a: Double, _ b: Double) -> Double {
        let difference = abs(a - b).truncatingRemainder(dividingBy: 24)
        return min(difference, 24 - difference)
    }
}

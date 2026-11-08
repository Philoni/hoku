import Foundation

/// The names rooms, lamps and scenes had before they were renamed (e.g. in the Hue
/// app), so voice commands and shortcuts created with an old name keep working.
/// Current names always win; a former name only resolves when nothing is called that now.
public struct NameHistory: Codable, Equatable, Sendable {
    /// Former names by resource ID, oldest first, at most a few per ID.
    public private(set) var formerNames: [String: [String]] = [:]

    private static let limit = 5

    public init() {}

    /// Notes that `id` was called `oldName` before it became `newName`.
    public mutating func record(id: String, oldName: String, newName: String) {
        guard !oldName.isEmpty, !Self.same(oldName, newName) else { return }
        var names = formerNames[id, default: []].filter { !Self.same($0, oldName) && !Self.same($0, newName) }
        names.append(oldName)
        formerNames[id] = Array(names.suffix(Self.limit))
        // Whoever is now called `newName` owns it; it's nobody's former name anymore.
        for (otherID, list) in formerNames where otherID != id {
            let remaining = list.filter { !Self.same($0, newName) }
            formerNames[otherID] = remaining.isEmpty ? nil : remaining
        }
    }

    /// Records every rename between two snapshots: same ID, different name.
    /// Returns whether anything changed.
    @discardableResult
    public mutating func recordRenames(from old: EntitySnapshot, to new: EntitySnapshot) -> Bool {
        let before = self
        func compare(_ old: [(String, String)], _ new: [(String, String)]) {
            let oldNames = Dictionary(old, uniquingKeysWith: { first, _ in first })
            for (id, name) in new {
                if let previous = oldNames[id] { record(id: id, oldName: previous, newName: name) }
            }
        }
        compare(old.rooms.map { ($0.id, $0.name) }, new.rooms.map { ($0.id, $0.name) })
        compare(old.lights.map { ($0.id, $0.name) }, new.lights.map { ($0.id, $0.name) })
        compare(old.scenes.map { ($0.id, $0.name) }, new.scenes.map { ($0.id, $0.name) })
        // Forget what no longer exists.
        let alive = Set(new.rooms.map(\.id) + new.lights.map(\.id) + new.scenes.map(\.id))
        formerNames = formerNames.filter { alive.contains($0.key) }
        return self != before
    }

    /// The one item among `items` that used to be called `spoken`, matched as tolerantly
    /// as current names are (spacing, accents, singular/plural). Nil when ambiguous.
    func match<Item: Identifiable>(_ spoken: String, in items: [Item]) -> Item? where Item.ID == String {
        let candidates = items.flatMap { item in (formerNames[item.id] ?? []).map { (item, $0) } }
        guard !candidates.isEmpty else { return nil }
        let levels: [(String) -> Bool] = [
            { Self.same($0, spoken) },
            { SpokenNames.normalized($0) == SpokenNames.normalized(spoken) },
            { SpokenNames.stem($0) == SpokenNames.stem(spoken) },
        ]
        for matches in levels {
            let ids = Set(candidates.filter { matches($0.1) }.map(\.0.id))
            if ids.count == 1 { return items.first { $0.id == ids.first } }
            if ids.count > 1 { return nil }
        }
        return nil
    }

    private static func same(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    // MARK: Storage

    static var file: URL { SharedStorage.directory.appending(path: "former-names.json") }

    public static func load() -> NameHistory {
        guard let data = try? Data(contentsOf: file) else { return NameHistory() }
        return (try? JSONDecoder().decode(NameHistory.self, from: data)) ?? NameHistory()
    }

    public func save() throws {
        try FileManager.default.createDirectory(at: SharedStorage.directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: Self.file, options: .atomic)
    }
}

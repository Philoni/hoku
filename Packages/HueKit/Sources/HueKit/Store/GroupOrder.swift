import Foundation

/// The user's own order for rooms and zones: pinned ones first, then a custom
/// sequence, then everything else by name. Stored by ID, so renaming keeps the order.
public struct GroupOrder: Codable, Equatable, Sendable {
    public var pinned: Set<String> = []
    /// Custom sequence; groups missing here (new rooms) follow by name.
    public var sequence: [String] = []

    public init() {}

    public var isCustom: Bool { !pinned.isEmpty || !sequence.isEmpty }

    public func sorted(_ groups: [HueGroup]) -> [HueGroup] {
        let position = Dictionary(sequence.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return groups.sorted { lhs, rhs in
            let pins = (pinned.contains(lhs.id), pinned.contains(rhs.id))
            if pins.0 != pins.1 { return pins.0 }
            switch (position[lhs.id], position[rhs.id]) {
            case let (left?, right?): return left < right
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
    }

    public mutating func togglePin(_ id: String) {
        if pinned.remove(id) == nil {
            pinned.insert(id)
        } else {
            // Its place in the sequence was a place among the pinned ones.
            sequence.removeAll { $0 == id }
        }
    }

    /// Moves a group one place up or down among the groups shown with it. Pinned and
    /// unpinned groups form separate blocks; a move never crosses between them.
    public mutating func move(_ id: String, up: Bool, in groups: [HueGroup]) {
        var ids = sorted(groups).map(\.id)
        guard let index = ids.firstIndex(of: id) else { return }
        let target = up ? index - 1 : index + 1
        guard ids.indices.contains(target), pinned.contains(ids[target]) == pinned.contains(id) else { return }
        ids.swapAt(index, target)
        // Keep the places of groups that are not part of this list (rooms vs. zones).
        let listed = Set(ids)
        sequence = ids + sequence.filter { !listed.contains($0) }
    }

    public func canMove(_ id: String, up: Bool, in groups: [HueGroup]) -> Bool {
        let ids = sorted(groups).map(\.id)
        guard let index = ids.firstIndex(of: id) else { return false }
        let target = up ? index - 1 : index + 1
        return ids.indices.contains(target) && pinned.contains(ids[target]) == pinned.contains(id)
    }
}

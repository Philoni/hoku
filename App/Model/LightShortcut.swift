import HueKit

/// A system-wide keyboard shortcut that acts on the lights without opening the panel.
struct LightShortcut: Codable, Equatable, Identifiable {
    enum Target: Codable, Hashable {
        case allOff
        /// Toggles a room or zone.
        case group(String)
        case scene(String)
    }

    var target: Target
    var combination: HotKey.Combination

    var id: Target { target }
}

/// What a shortcut just did, shown briefly under the menu bar icon: a key press
/// has no other visible answer when the lamps are in another room.
struct ShortcutFeedback: Equatable {
    var title: String
    var detail: String
    var systemImage: String
    var isProblem = false
}

extension AppModel {
    func combination(for target: LightShortcut.Target) -> HotKey.Combination? {
        shortcuts.first { $0.target == target }?.combination
    }

    /// `nil` removes the shortcut. A combination moves to its new target; the one
    /// that opens Hoku is never taken away, so that returns `false`.
    @discardableResult
    func setCombination(_ combination: HotKey.Combination?, for target: LightShortcut.Target) -> Bool {
        if let combination, combination == hotKeyCombination { return false }
        var updated = shortcuts.filter { $0.target != target }
        if let combination {
            updated.removeAll { $0.combination == combination }
            updated.append(LightShortcut(target: target, combination: combination))
        }
        shortcuts = updated
        return true
    }

    func perform(_ target: LightShortcut.Target) -> ShortcutFeedback {
        guard store.connection == .live else {
            return ShortcutFeedback(title: "Keine Verbindung", detail: "Die Bridge ist gerade nicht erreichbar", systemImage: "wifi.slash", isProblem: true)
        }
        switch target {
        case .allOff:
            store.setAllOff()
            return ShortcutFeedback(title: "Alles aus", detail: "Alle Räume", systemImage: "power")
        case let .group(id):
            guard let group = store.group(id) else { return .missing }
            let turnsOn = store.groupedLight(for: group)?.isOn != true
            store.setOn(turnsOn, group: group)
            return ShortcutFeedback(title: group.name, detail: turnsOn ? "An" : "Aus", systemImage: turnsOn ? "lightbulb.fill" : "lightbulb")
        case let .scene(id):
            guard let scene = store.scenes[id] else { return .missing }
            store.recall(scene)
            let room = scene.group.flatMap { store.group($0.rid) }?.name ?? "Szene"
            return ShortcutFeedback(title: scene.name, detail: room, systemImage: "sparkles")
        }
    }
}

private extension ShortcutFeedback {
    /// The room or scene was deleted in the Hue app after the shortcut was set.
    static let missing = ShortcutFeedback(
        title: "Nicht mehr vorhanden", detail: "Kürzel in den Einstellungen neu zuweisen",
        systemImage: "questionmark.circle", isProblem: true
    )
}

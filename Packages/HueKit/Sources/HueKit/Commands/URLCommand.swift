import Foundation

/// `hoku://` commands, so Shortcuts ("URL öffnen"), Raycast, scripts etc. can
/// drive the app until App Intents are available. German and English verbs work.
///
///     hoku://szene/Entspannen?raum=Wohnzimmer&modus=dynamisch
///     hoku://raum/Wohnzimmer/an?helligkeit=40
///     hoku://lampe/Stehlampe/umschalten
///     hoku://alle/aus
///     hoku://oeffnen · hoku://schliessen · hoku://einrichtung
public enum URLCommand: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case on, off, toggle

        public init?(_ word: String?) {
            switch word?.lowercased() {
            case nil, "", "an", "on", "ein": self = .on
            case "aus", "off": self = .off
            case "umschalten", "toggle": self = .toggle
            default: return nil
            }
        }
    }

    case scene(name: String, group: String?, mode: HueStore.SceneRecall)
    case group(name: String, action: Action, brightness: Double?)
    case light(name: String, action: Action, brightness: Double?)
    case allOff
    case openPanel
    case closePanel
    case openSetup

    public init?(url: URL) {
        guard url.scheme == "hoku", let kind = url.host()?.lowercased() else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        let query = Dictionary(
            (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
                .compactMap { item in item.value.map { (item.name.lowercased(), $0) } },
            uniquingKeysWith: { $1 }
        )
        let brightness = (query["helligkeit"] ?? query["brightness"]).flatMap(Double.init)

        switch kind {
        case "szene", "scene":
            guard let name = parts.first else { return nil }
            let mode: HueStore.SceneRecall = switch (query["modus"] ?? query["mode"])?.lowercased() {
            case "dynamisch", "dynamic": .dynamic
            case "statisch", "static": .static
            default: .active
            }
            self = .scene(name: name, group: query["raum"] ?? query["room"], mode: mode)
        case "raum", "room", "zone":
            guard let name = parts.first, let action = Action(parts.dropFirst().first) else { return nil }
            self = .group(name: name, action: action, brightness: brightness)
        case "lampe", "light":
            guard let name = parts.first, let action = Action(parts.dropFirst().first) else { return nil }
            self = .light(name: name, action: action, brightness: brightness)
        case "alle", "all":
            // Only "off" exists for everything; "hoku://alle/an" must not switch all off.
            guard parts.first == nil || Action(parts.first) == .off else { return nil }
            self = .allOff
        case "oeffnen", "öffnen", "open", "panel":
            self = .openPanel
        case "schliessen", "schließen", "close":
            self = .closePanel
        case "einrichtung", "setup":
            self = .openSetup
        default:
            return nil
        }
    }

    /// Runs the command. Returns an error message for the user, or nil on success.
    @MainActor
    public func run(on store: HueStore) -> String? {
        switch self {
        case let .scene(name, groupName, mode):
            let group = groupName.flatMap { store.findGroup(named: $0) }
            if let groupName, group == nil { return String(localized: "Raum „\(groupName)“ nicht gefunden.", bundle: .module) }
            guard let scene = store.findScene(named: name, in: group) else {
                return String(localized: "Szene „\(name)“ nicht gefunden.", bundle: .module)
            }
            store.recall(scene, as: mode)

        case let .group(name, action, brightness):
            guard let group = store.findGroup(named: name) else { return String(localized: "Raum „\(name)“ nicht gefunden.", bundle: .module) }
            let isOn = store.groupedLight(for: group)?.isOn ?? false
            if let brightness, action != .off {
                store.setBrightness(brightness, group: group)
            } else {
                store.setOn(action == .toggle ? !isOn : action == .on, group: group)
            }

        case let .light(name, action, brightness):
            guard let light = store.findLight(named: name) else { return String(localized: "Lampe „\(name)“ nicht gefunden.", bundle: .module) }
            if let brightness, action != .off, light.supportsDimming {
                store.setBrightness(brightness, light: light)
            } else {
                store.setOn(action == .toggle ? !light.isOn : action == .on, light: light)
            }

        case .allOff:
            store.setAllOff()
        case .openPanel, .closePanel, .openSetup:
            break // handled by the app delegate, which owns the panel
        }
        return nil
    }
}

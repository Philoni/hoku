import AppKit
import HueKit

enum AppearanceMode: String, Codable, CaseIterable {
    case automatic, dark, light

    var title: String {
        switch self {
        case .automatic: "Automatisch"
        case .dark: "Dunkel"
        case .light: "Hell"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .automatic: nil
        case .dark: NSAppearance(named: .darkAqua)
        case .light: NSAppearance(named: .aqua)
        }
    }
}

/// "Lights off when I leave the Mac": lock, display sleep or lid closed.
struct AwayAutomation: Codable, Equatable {
    var isEnabled = false
    /// Rooms/zones to switch off; empty means all rooms.
    var groupIDs: [String] = []
    var restoresOnReturn = true
}

/// Small typed wrapper around UserDefaults for Codable preferences.
enum Preferences {
    static func load<T: Decodable>(_ key: String) -> T? {
        // Settings saved under the app's former identity ("Lichtblick") serve as a fallback.
        let previous = UserDefaults(suiteName: "de.lichtblick.menubar")
        guard let data = UserDefaults.standard.data(forKey: key) ?? previous?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, as key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key)
    }
}

/// Persists the usage log next to the bridge credentials.
enum UsageFile {
    private static var url: URL { CredentialStore.directory.appending(path: "usage.json") }

    static func load() -> UsageLog {
        // Fall back to what earlier versions (e.g. "Lichtblick") learned.
        let candidates = [url] + SharedStorage.previousDirectories.map { $0.appending(path: "usage.json") }
        for candidate in candidates {
            if let data = try? Data(contentsOf: candidate), let log = try? JSONDecoder().decode(UsageLog.self, from: data) {
                return log
            }
        }
        return UsageLog()
    }

    static func save(_ log: UsageLog) {
        try? FileManager.default.createDirectory(at: CredentialStore.directory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(log).write(to: url, options: .atomic)
    }
}

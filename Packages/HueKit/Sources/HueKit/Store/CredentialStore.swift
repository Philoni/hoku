import Foundation

/// Where Hoku keeps files that the app, its Siri actions and its Control Center
/// extension all need: the App Group container when the build has one (Xcode builds
/// set `LBAppGroup` in Info.plist), otherwise Application Support.
public enum SharedStorage {
    /// Only a team-prefixed group ("ABCDE12345.io.github.philoni.hoku.shared") is usable. Builds
    /// without a signing team would get a bare ID, and touching such a container makes
    /// macOS ask the user for access to "data from other apps" — so skip it then.
    public static var groupIdentifier: String? {
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: "LBAppGroup") as? String,
              let prefix = identifier.split(separator: ".").first,
              prefix.count == 10,
              prefix.allSatisfy({ $0.isUppercase || $0.isNumber })
        else { return nil }
        return identifier
    }

    public static var directory: URL {
        if let groupIdentifier,
           let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) {
            return container
        }
        return legacyDirectory
    }

    /// Fallback for builds without an App Group (e.g. unsigned development builds).
    static var legacyDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Hoku", directoryHint: .isDirectory)
    }

    /// Where earlier versions kept their files: Application Support of the fallback
    /// directory, and of the app's former name "Lichtblick".
    public static var previousDirectories: [URL] {
        [
            legacyDirectory,
            URL.applicationSupportDirectory.appending(path: "Lichtblick", directoryHint: .isDirectory),
        ].filter { $0 != directory }
    }
}

/// Persists the bridge credentials as a 0600 file in the shared container.
///
/// A file rather than the Keychain, so the sandboxed Control Center extension can
/// read it without Keychain access groups. (Approach adapted from jurre/huebar, MIT.)
public enum CredentialStore {
    public static var directory: URL { SharedStorage.directory }

    static var file: URL { directory.appending(path: "bridge.json") }

    public static func load() -> BridgeCredentials? {
        if let data = try? Data(contentsOf: file) {
            return try? JSONDecoder().decode(BridgeCredentials.self, from: data)
        }
        return migrateFromLegacyLocation()
    }

    /// Earlier builds kept the key in Application Support (also under the old name
    /// "Lichtblick"); copy it over once. The old file stays, so switching back keeps working.
    private static func migrateFromLegacyLocation() -> BridgeCredentials? {
        for directory in SharedStorage.previousDirectories {
            guard let data = try? Data(contentsOf: directory.appending(path: "bridge.json")),
                  let credentials = try? JSONDecoder().decode(BridgeCredentials.self, from: data)
            else { continue }
            try? save(credentials)
            return credentials
        }
        return nil
    }

    public static func save(_ credentials: BridgeCredentials) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try writeRestricted(try encoder.encode(credentials), to: file)
    }

    public static func delete() {
        try? FileManager.default.removeItem(at: file)
    }

    /// Writes a 0600 temporary file next to `url` and renames it over the target.
    /// The key is never world-readable, not even briefly (`Data.write(options: .atomic)`
    /// would create the file 0644 first), and a crash mid-write leaves the old file intact.
    static func writeRestricted(_ data: Data, to url: URL) throws {
        let temporary = url.deletingLastPathComponent()
            .appending(path: ".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        do {
            defer { close(descriptor) }
            try data.withUnsafeBytes { buffer in
                guard let base = buffer.baseAddress else { return }
                var written = 0
                while written < buffer.count {
                    let result = write(descriptor, base.advanced(by: written), buffer.count - written)
                    guard result >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
                    written += result
                }
            }
            guard fsync(descriptor) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        } catch {
            unlink(temporary.path)
            throw error
        }
        guard rename(temporary.path, url.path) == 0 else {
            let error = POSIXError(.init(rawValue: errno) ?? .EIO)
            unlink(temporary.path)
            throw error
        }
    }
}

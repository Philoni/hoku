import AppKit

/// Where Hoku runs from, and moving it to Applications.
///
/// A downloaded app that wasn't moved in the Finder runs from a random read-only path
/// (App Translocation). Permissions, launch at login and Siri shortcuts would then
/// attach to the wrong copy, so setup offers to move Hoku first.
enum InstallLocation {
    enum Status: Equatable {
        /// In /Applications or ~/Applications: all good.
        case applications
        /// Started from a quarantined download; `original` is where the user put it.
        case translocated(original: URL)
        /// Running straight from a mounted disk image.
        case diskImage(URL)
        /// Anywhere else, e.g. Downloads or the Desktop.
        case elsewhere(URL)

        var needsMove: Bool { self != .applications }
    }

    static var current: Status {
        let bundle = Bundle.main.bundleURL
        if let original = translocatedOriginal(of: bundle) { return .translocated(original: original) }
        let path = bundle.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix("/Applications/") || path.hasPrefix(home + "/Applications/") { return .applications }
        if path.hasPrefix("/Volumes/") { return .diskImage(bundle) }
        // Development builds (Xcode, build scripts) are left alone.
        if path.contains("DerivedData") || path.contains("/Build/Products/") { return .applications }
        return .elsewhere(bundle)
    }

    /// Other installed copies, which confuse Siri and the local network permission.
    static var duplicates: [URL] {
        let me = Bundle.main.bundleURL.standardizedFileURL
        let id = Bundle.main.bundleIdentifier ?? "io.github.philoni.hoku"
        return NSWorkspace.shared.urlsForApplications(withBundleIdentifier: id)
            .map(\.standardizedFileURL)
            .filter { $0 != me && !$0.path.contains("DerivedData") && !$0.path.contains("/AppTranslocation/") }
    }

    // MARK: Moving

    enum MoveError: LocalizedError {
        case noWritableApplicationsFolder

        var errorDescription: String? {
            "Kein beschreibbarer Programme-Ordner gefunden. Zieh Hoku bitte im Finder nach „Programme“."
        }
    }

    /// Moves (or, from a disk image, copies) Hoku to Applications, lifts the quarantine
    /// so it isn't translocated again, and relaunches from there.
    static func moveToApplicationsAndRelaunch() throws {
        let fileManager = FileManager.default
        let source: URL
        var copies = false
        switch current {
        case .applications: return
        case let .translocated(original): source = original
        case let .diskImage(url): source = url; copies = true
        case let .elsewhere(url): source = url
        }

        let destinationFolder = try applicationsFolder()
        let destination = destinationFolder.appending(path: source.lastPathComponent)
        if fileManager.fileExists(atPath: destination.path) {
            // An older version: to the Trash, so the path (and its permissions) stays the same.
            try fileManager.trashItem(at: destination, resultingItemURL: nil)
        }
        if copies {
            try fileManager.copyItem(at: source, to: destination)
        } else {
            try fileManager.moveItem(at: source, to: destination)
        }
        removeQuarantine(from: destination)
        relaunch(at: destination, ejecting: copies ? source.deletingLastPathComponent() : nil)
    }

    private static func applicationsFolder() throws -> URL {
        let system = URL(filePath: "/Applications")
        if FileManager.default.isWritableFile(atPath: system.path) { return system }
        let user = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications")
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        guard FileManager.default.isWritableFile(atPath: user.path) else { throw MoveError.noWritableApplicationsFolder }
        return user
    }

    /// The user already approved Hoku ("Dennoch öffnen"); without this, a move outside
    /// the Finder would get it translocated again on the next launch.
    private static func removeQuarantine(from url: URL) {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/xattr")
        process.arguments = ["-dr", "com.apple.quarantine", url.path]
        try? process.run()
        process.waitUntilExit()
    }

    /// Waits for this process to exit, then opens the new copy (and ejects the disk image).
    private static func relaunch(at url: URL, ejecting volume: URL?) {
        let pid = ProcessInfo.processInfo.processIdentifier
        var script = "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.1; done; /usr/bin/open \(quoted(url.path))"
        if let volume { script += "; /usr/bin/hdiutil detach \(quoted(volume.path)) -quiet" }
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", script]
        try? process.run()
        NSApp.terminate(nil)
    }

    private static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: Translocation

    private typealias IsTranslocated = @convention(c) (CFURL, UnsafeMutablePointer<Bool>, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Bool
    private typealias OriginalPath = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?

    /// Uses Security's (private but long-stable) translocation calls, like LetsMove does;
    /// falls back to the path pattern if they ever disappear.
    private static func translocatedOriginal(of bundle: URL) -> URL? {
        guard let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let isTranslocatedSymbol = dlsym(handle, "SecTranslocateIsTranslocatedURL"),
              let originalSymbol = dlsym(handle, "SecTranslocateCreateOriginalPathForURL")
        else {
            return bundle.path.contains("/AppTranslocation/") ? bundle : nil
        }
        var isTranslocated = false
        let isTranslocatedFunction = unsafeBitCast(isTranslocatedSymbol, to: IsTranslocated.self)
        guard isTranslocatedFunction(bundle as CFURL, &isTranslocated, nil), isTranslocated else { return nil }
        let originalFunction = unsafeBitCast(originalSymbol, to: OriginalPath.self)
        return originalFunction(bundle as CFURL, nil)?.takeRetainedValue() as URL?
    }
}

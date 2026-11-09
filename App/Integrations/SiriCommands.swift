import AppKit
import HueKit
import Security

/// Natural voice commands ("Hey Siri, Zimmer an") without the app name.
///
/// Apple only lets third-party Siri phrases through with the app's name, and Siri's
/// Home domain claims "<room> an/aus" for Apple Home. Personal shortcuts, however, are
/// matched by their name first. So Hoku generates one shortcut per command — a single
/// "Open URLs" action with a `hoku://` command — signs it with the system's
/// `shortcuts` tool and hands it to the Shortcuts app, where the user confirms once.
/// Which commands to offer is decided in HueKit (`SiriCommand.proposals`).
@MainActor
enum SiriCommands {
    /// Whether the Mac is signed in with an Apple Account. `shortcuts sign` and the
    /// Shortcuts app's import both need it. Read-only, no entitlement required.
    static var isSignedIntoICloud: Bool {
        let accounts = UserDefaults(suiteName: "MobileMeAccounts")?.array(forKey: "Accounts") ?? []
        return !accounts.isEmpty
    }

    // MARK: Existing shortcuts

    /// Names of the user's shortcuts, so commands that already exist aren't added twice.
    static func existingShortcutNames() async -> Set<String> {
        guard let output = try? await run("/usr/bin/shortcuts", ["list"]) else { return [] }
        return Set(output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
    }

    // MARK: Installing

    enum InstallError: LocalizedError {
        case signing(String)

        var errorDescription: String? {
            switch self {
            case let .signing(detail):
                String(localized: "Kurzbefehl konnte nicht signiert werden. Bist du in macOS mit deinem Apple Account (iCloud) angemeldet? (\(detail))")
            }
        }
    }

    /// Builds, signs and opens one shortcut per command. Each opens the Shortcuts app's
    /// "Add Shortcut" sheet; `progress` reports how many were handed over.
    static func install(_ commands: [SiriCommand], progress: @escaping (Int) -> Void) async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "HokuSiriCommands-\(UUID().uuidString)")
        let unsigned = folder.appending(path: "unsigned")
        let signed = folder.appending(path: "signed")
        try FileManager.default.createDirectory(at: unsigned, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: signed, withIntermediateDirectories: true)

        for (index, command) in commands.enumerated() {
            // The file name becomes the shortcut's name, which is what Siri listens for.
            let fileName = command.name.replacingOccurrences(of: "/", with: "-") + ".shortcut"
            let input = unsigned.appending(path: fileName)
            let output = signed.appending(path: fileName)
            try workflow(for: command).write(to: input)

            // Signing goes through Apple's servers, which occasionally answer 502: retry.
            var lastError: Error?
            for attempt in 1...3 where !FileManager.default.fileExists(atPath: output.path) {
                do {
                    _ = try await run("/usr/bin/shortcuts", ["sign", "--mode", "anyone", "--input", input.path, "--output", output.path])
                } catch {
                    lastError = error
                    try? await Task.sleep(for: .seconds(Double(attempt) * 1.5))
                }
            }
            if let lastError, !FileManager.default.fileExists(atPath: output.path) {
                throw InstallError.signing(lastError.localizedDescription)
            }
            guard FileManager.default.fileExists(atPath: output.path) else {
                throw InstallError.signing(String(localized: "keine Ausgabe"))
            }

            NSWorkspace.shared.open(output)
            progress(index + 1)
            // Give the Shortcuts app a moment, so the sheets queue up in order.
            try? await Task.sleep(for: .milliseconds(900))
        }
    }

    /// The team identifier of this build's signature. Shortcuts addresses an app's own
    /// actions by bundle ID *and* team ID, so a build signed without a team (the
    /// self-signed public release) falls back to "Open URLs" shortcuts.
    static let teamIdentifier: String? = {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any]
        else { return nil }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }()

    /// Whether shortcuts can run Hoku's own actions (no first-run question) or must
    /// open a `hoku://` URL (macOS asks once per shortcut whether it may open Hoku).
    static var usesAppActions: Bool { teamIdentifier != nil }

    /// A shortcut with a single action. Preferably Hoku's own App Intent (the format
    /// Shortcuts itself writes); otherwise "Open URLs" with the URL as a text token
    /// string inside the action — a separate "URL" action fails when Siri runs it.
    static func workflow(for command: SiriCommand) throws -> Data {
        let action: [String: Any] = if let teamIdentifier {
            intentAction(for: command, teamIdentifier: teamIdentifier)
        } else {
            [
                "WFWorkflowActionIdentifier": "is.workflow.actions.openurl",
                "WFWorkflowActionParameters": [
                    "WFInput": [
                        "Value": ["string": command.url, "attachmentsByRange": [String: Any]()],
                        "WFSerializationType": "WFTextTokenString",
                    ],
                ],
            ]
        }
        // Mirrors what the Shortcuts app on macOS 26 writes itself.
        let plist: [String: Any] = [
            "WFWorkflowMinimumClientVersion": 900,
            "WFWorkflowMinimumClientVersionString": "900",
            "WFWorkflowClientVersion": "4711.1.1",
            "WFWorkflowHasOutputFallback": false,
            "WFWorkflowIcon": [
                "WFWorkflowIconStartColor": command.switchesOff ? 255 : 4_282_601_983,
                "WFWorkflowIconGlyphNumber": command.switchesOff ? 59446 : 59511,
            ],
            "WFWorkflowImportQuestions": [Any](),
            "WFWorkflowTypes": ["WFWorkflowTypeShowInSearch"],
            "WFWorkflowInputContentItemClasses": [
                "WFAppContentItem", "WFAppStoreAppContentItem", "WFArticleContentItem", "WFContactContentItem",
                "WFDateContentItem", "WFEmailAddressContentItem", "WFFolderContentItem", "WFGenericFileContentItem",
                "WFImageContentItem", "WFiTunesProductContentItem", "WFLocationContentItem", "WFDCMapsLinkContentItem",
                "WFAVAssetContentItem", "WFPDFContentItem", "WFPhoneNumberContentItem", "WFRichTextContentItem",
                "WFSafariWebPageContentItem", "WFStringContentItem", "WFURLContentItem",
            ],
            "WFWorkflowOutputContentItemClasses": [Any](),
            "WFWorkflowHasShortcutInputVariables": false,
            "WFQuickActionSurfaces": [Any](),
            "WFWorkflowActions": [action],
        ]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    }

    private static func intentAction(for command: SiriCommand, teamIdentifier: String) -> [String: Any] {
        let bundleID = Bundle.main.bundleIdentifier ?? "io.github.philoni.hoku"
        func entity(_ id: String, _ title: String, _ subtitle: String?, _ symbol: String) -> [String: Any] {
            var value: [String: Any] = [
                "identifier": id,
                "title": ["key": title],
                "symbol": ["systemName": symbol],
            ]
            if let subtitle { value["subtitle"] = ["key": subtitle] }
            return value
        }
        let intent: String
        var parameters: [String: Any] = [:]
        switch command.action {
        case let .roomPower(id, name, isZone, on):
            intent = "SetRoomPowerIntent"
            parameters["room"] = entity(id, name, isZone ? String(localized: "Zone") : String(localized: "Raum"), isZone ? "square.on.square" : "house.fill")
            parameters["value"] = on ? 1 : 0
        case let .lightPower(id, name, roomName, on):
            intent = "SetLightPowerIntent"
            parameters["light"] = entity(id, name, roomName, "lightbulb.fill")
            parameters["value"] = on ? 1 : 0
        case let .scene(id, name, roomName):
            intent = "ActivateSceneIntent"
            parameters["scene"] = entity(id, name, roomName, "sparkles")
        case .allOff:
            intent = "AllOffIntent"
        }
        parameters["AppIntentDescriptor"] = [
            "AppIntentIdentifier": intent,
            "BundleIdentifier": bundleID,
            "Name": "Hoku",
            "TeamIdentifier": teamIdentifier,
        ]
        parameters["ShowWhenRun"] = false
        parameters["UUID"] = UUID().uuidString
        return [
            "WFWorkflowActionIdentifier": "\(bundleID).\(intent)",
            "WFWorkflowActionParameters": parameters,
        ]
    }

    // MARK: Process helper

    /// Runs a tool and returns its output. The output is read while the process runs:
    /// reading only at exit would deadlock once it fills the pipe (hundreds of shortcuts).
    private static func run(_ executable: String, _ arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()

        let output = await Task.detached {
            (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        }.value
        let status: Int32 = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus)
            }
        }

        let text = String(decoding: output, as: UTF8.self)
        guard status == 0 else {
            throw NSError(
                domain: "Hoku.Shortcuts", code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: text.trimmingCharacters(in: .whitespacesAndNewlines)]
            )
        }
        return text
    }
}

private extension SiriCommand {
    var switchesOff: Bool {
        switch action {
        case let .roomPower(_, _, _, on), let .lightPower(_, _, _, on): !on
        case .allOff: true
        case .scene: false
        }
    }
}

import AppKit
import HueKit
import SwiftUI

/// Development aid: `HOKU_SNAPSHOT=<dir> Hoku.app/Contents/MacOS/Hoku`
/// renders the main pages with live data to PNGs and quits. Glass materials don't
/// render offscreen, so a dark backdrop stands in for the popover.
@MainActor
enum Snapshot {
    static var isRequested: Bool { ProcessInfo.processInfo.environment["HOKU_SNAPSHOT"] != nil }
    /// `HOKU_DEMO=1`: a made-up home instead of the paired bridge, for screenshots
    /// without personal data. Nothing is read from or written to the real setup.
    static var isDemo: Bool { ProcessInfo.processInfo.environment["HOKU_DEMO"] != nil }

    static func runIfRequested(model: AppModel) {
        if let directory = ProcessInfo.processInfo.environment["HOKU_SHORTCUT_EXPORT"] {
            exportShortcuts(to: directory, model: model)
            return
        }
        guard let directory = ProcessInfo.processInfo.environment["HOKU_SNAPSHOT"] else { return }
        Task {
            if isDemo {
                model.store.showDemo()
            } else {
                await model.store.refresh()
            }
            let store = model.store
            let status = "connection: \(store.connection)\ncredentials: \(store.credentials?.host ?? "none")\nstorage: \(SharedStorage.directory.path)\n"
            try? status.write(to: URL(fileURLWithPath: directory).appending(path: "status.txt"), atomically: true, encoding: .utf8)
            let room = store.sortedRooms.max { store.scenes(in: $0).count < store.scenes(in: $1).count }
            let roomWithZone = store.sortedRooms.first { !store.zones(in: $0).isEmpty }
            let light = store.lights.values.first { $0.supportsColor && $0.isOn } ?? store.lights.values.first { $0.supportsColor }

            var pages: [(String, AnyView)] = [
                ("home", AnyView(HomeView(push: { _ in }))),
                ("home-keyboard", AnyView(HomeView(push: { _ in }, selection: 1))),
            ]
            let expanded = PanelPresentation()
            // The most lit room makes the nicest picture.
            if let roomWithLamps = store.sortedRooms.max(by: { lhs, rhs in
                (store.lights(in: lhs).filter(\.isOn).count, store.lights(in: lhs).count)
                    < (store.lights(in: rhs).filter(\.isOn).count, store.lights(in: rhs).count)
            }) {
                expanded.expandedRoomID = roomWithLamps.id
                pages.append(("home-expanded", AnyView(HomeView(push: { _ in }).environment(expanded))))
            }
            if let room {
                pages.append(("room", AnyView(GroupDetailView(group: room, push: { _ in }, pop: {}))))
            }
            if let roomWithZone {
                pages.append(("room-zone", AnyView(GroupDetailView(group: roomWithZone, push: { _ in }, pop: {}))))
            }
            if let light {
                pages.append(("light", AnyView(LightDetailView(light: light, pop: {}))))
            }
            pages.append(("settings", AnyView(SettingsView(push: { _ in }, pop: {}))))
            pages.append(("routines", AnyView(RoutinesView(pop: {}))))
            pages.append(("routine-new", AnyView(RoutinesView(pop: {}, newRoutine: .wakeUp))))
            pages.append(("devices", AnyView(DevicesView(pop: {}))))
            if Features.awayReminder {
                pages.append(("unterwegs", AnyView(LeftOnReminderView(pop: {}))))
            }
            pages.append(("sync", AnyView(SyncChip(area: EntertainmentArea(id: "demo-area", name: String(localized: "Wohnzimmer"), status: "active")))))
            pages.append(("raeume-ordnen", AnyView(RoomOrderView(pop: {}))))
            pages.append(("verbindung", AnyView(ConnectionDetailsView(pop: {}))))
            pages.append(("tastenkuerzel", AnyView(ShortcutsView(pop: {}))))
            pages.append(("kuerzel-antwort", AnyView(ShortcutFeedbackView(feedback: ShortcutFeedback(title: "Wohnzimmer", detail: "An", systemImage: "lightbulb.fill")))))
            pages.append(("mitteilung-bild", AnyView(NotificationArt(colors: store.colorsOfLightsOn))))

            let scheme: ColorScheme = ProcessInfo.processInfo.environment["HOKU_SNAPSHOT_SCHEME"] == "light" ? .light : .dark
            for (name, page) in pages {
                let view = page
                    .padding(12)
                    .frame(width: Theme.width)
                    .fixedSize(horizontal: false, vertical: true)
                    .background {
                        ZStack {
                            scheme == .dark ? Color(red: 0.16, green: 0.15, blue: 0.16) : Color(red: 0.93, green: 0.92, blue: 0.93)
                            AmbientBackground(colors: store.colorsOfLightsOn)
                        }
                    }
                .fontDesign(.rounded)
                .environment(model)
                .environment(store)
                .environment(PanelPresentation())
                .environment(\.colorScheme, scheme)
                .environment(\.isSnapshot, true)

                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                // Let staggered appear animations settle.
                try? await Task.sleep(for: .milliseconds(600))
                if let image = renderer.nsImage,
                   let tiff = image.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: directory).appending(path: "\(name).png"))
                }
            }

            // The setup assistant, one image per step.
            for step in WizardModel.Step.allCases {
                let wizard = WizardModel(app: model, mode: .fullSetup)
                wizard.preview(step)
                let view = WizardView(model: wizard)
                    .environment(model)
                    .environment(store)
                    .environment(PanelPresentation())
                    .environment(\.isSnapshot, true)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                try? await Task.sleep(for: .milliseconds(300))
                if let image = renderer.nsImage,
                   let tiff = image.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: directory).appending(path: "wizard-\(step.rawValue)-\(step).png"))
                }
            }
            NSApplication.shared.terminate(nil)
        }
    }

    /// `HOKU_SHORTCUT_EXPORT=<dir>`: writes every proposed Siri shortcut as an unsigned
    /// .shortcut file, to inspect the format without the Shortcuts app.
    private static func exportShortcuts(to directory: String, model: AppModel) {
        Task {
            if isDemo { model.store.showDemo() } else { await model.store.refresh() }
            let folder = URL(fileURLWithPath: directory)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for command in SiriCommand.proposals(for: model.store) {
                let file = folder.appending(path: command.name.replacingOccurrences(of: "/", with: "-") + ".shortcut")
                try? SiriCommands.workflow(for: command).write(to: file)
            }
            try? "team: \(SiriCommands.teamIdentifier ?? "none")\n".write(to: folder.appending(path: "info.txt"), atomically: true, encoding: .utf8)
            NSApplication.shared.terminate(nil)
        }
    }
}

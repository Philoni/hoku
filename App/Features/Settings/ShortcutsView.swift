import AppKit
import HueKit
import SwiftUI

struct ShortcutsView: View {
    @Environment(AppModel.self) private var model
    @Environment(HueStore.self) private var store
    let pop: () -> Void

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 10) {
            PageHeader(title: String(localized: "Tastenkürzel"), onBack: pop) { EmptyView() }

            PageScroll(maxHeight: 440) {
                VStack(spacing: 7) {
                    Text(notice ?? String(localized: "Funktionieren überall am Mac, auch wenn Hoku geschlossen ist."))
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(notice == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                        .contentTransition(.opacity)
                        .animation(Theme.spring, value: notice)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)

                    card {
                        HStack {
                            RowLabel(title: String(localized: "Hoku öffnen"), systemImage: "menubar.arrow.up.rectangle")
                            Spacer()
                            if model.isPanelHotKeyUnavailable { TakenBadge() }
                            HotKeyRecorder(combination: Binding(
                                get: { model.hotKeyCombination },
                                set: { if let new = $0 { model.hotKeyCombination = new } }
                            ), isRequired: true, name: String(localized: "Hoku öffnen"))
                        }
                        Divider().opacity(0.4)
                        row(String(localized: "Alles aus"), systemImage: "power", target: .allOff)
                    }

                    if !store.sortedRooms.isEmpty {
                        SectionTitle(text: String(localized: "Räume"), trailing: String(localized: "an / aus"))
                        card { rows(for: store.sortedRooms) }
                    }
                    if !store.sortedZones.isEmpty {
                        SectionTitle(text: String(localized: "Zonen"), trailing: String(localized: "an / aus"))
                        card { rows(for: store.sortedZones) }
                    }

                    SectionTitle(text: String(localized: "Szenen"))
                    card {
                        ForEach(sceneShortcuts) { shortcut in
                            if case let .scene(id) = shortcut.target {
                                row(sceneTitle(id), systemImage: "sparkles", target: shortcut.target)
                                Divider().opacity(0.4)
                            }
                        }
                        sceneMenu
                    }
                }
            }
        }
    }

    private var sceneShortcuts: [LightShortcut] {
        model.shortcuts.filter { if case .scene = $0.target { true } else { false } }
    }

    private func sceneTitle(_ id: String) -> String {
        guard let scene = store.scenes[id] else { return String(localized: "Gelöschte Szene") }
        let room = scene.group.flatMap { store.group($0.rid) }?.name
        return room.map { "\(scene.name) · \($0)" } ?? scene.name
    }

    @State private var notice: String?

    /// A scene gets its row once a combination is recorded for it.
    @State private var pendingScene: String?

    @ViewBuilder
    private var sceneMenu: some View {
        if let pendingScene {
            HStack {
                RowLabel(title: sceneTitle(pendingScene), systemImage: "sparkles")
                Spacer()
                HotKeyRecorder(combination: Binding(
                    get: { nil },
                    set: {
                        assign($0, to: .scene(pendingScene))
                        self.pendingScene = nil
                    }
                ), startsRecording: true, onCancel: { self.pendingScene = nil }, name: sceneTitle(pendingScene))
            }
        } else {
            Menu {
                ForEach(store.sortedRooms + store.sortedZones) { group in
                    let scenes = store.scenes(in: group)
                    if !scenes.isEmpty {
                        Menu(group.name) {
                            ForEach(scenes) { scene in
                                Button(scene.name) { pendingScene = scene.id }
                            }
                        }
                    }
                }
            } label: {
                RowLabel(title: String(localized: "Szene hinzufügen"), systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        }
    }

    @ViewBuilder
    private func rows(for groups: [HueGroup]) -> some View {
        ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
            if index > 0 { Divider().opacity(0.4) }
            row(group.name, systemImage: Icons.room(group.metadata?.archetype), target: .group(group.id))
        }
    }

    private func row(_ title: String, systemImage: String, target: LightShortcut.Target) -> some View {
        HStack {
            RowLabel(title: title, systemImage: systemImage)
            Spacer()
            if model.unavailableShortcuts.contains(target) { TakenBadge() }
            HotKeyRecorder(combination: Binding(
                get: { model.combination(for: target) },
                set: { assign($0, to: target) }
            ), name: title)
        }
    }

    private func assign(_ combination: HotKey.Combination?, to target: LightShortcut.Target) {
        guard !model.setCombination(combination, for: target) else { return }
        notice = String(localized: "\(model.hotKeyCombination.displayString) öffnet schon Hoku.")
        Task {
            try? await Task.sleep(for: .seconds(3))
            notice = nil
        }
    }

    private func card(@ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 10, content: content)
            .font(.system(size: 12.5, weight: .medium, design: .rounded))
            .padding(12)
            .background(CardBackground())
    }
}

/// Room symbols differ in width; a fixed column keeps the names aligned.
private struct RowLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage).frame(width: 22)
            Text(title).lineLimit(1)
        }
    }
}

private struct TakenBadge: View {
    var body: some View {
        Text("belegt")
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(.orange)
            .help("Eine andere App nutzt diese Tastenkombination bereits.")
    }
}

/// Click, then press the new shortcut. Esc cancels, ⌫ removes it.
struct HotKeyRecorder: View {
    @Environment(AppModel.self) private var model
    @Binding var combination: HotKey.Combination?
    /// The shortcut can be changed but not removed.
    var isRequired = false
    var startsRecording = false
    var onCancel: () -> Void = {}
    var name: String = ""

    @State private var id = UUID()
    @State private var monitor: Any?

    private var isRecording: Bool { model.activeRecorder == id }

    var body: some View {
        Button {
            isRecording ? cancel() : start()
        } label: {
            Text(isRecording ? String(localized: "Kürzel drücken …") : combination?.displayString ?? String(localized: "Festlegen"))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(combination == nil && !isRecording ? .secondary : .primary)
                .frame(minWidth: 70)
                .contentTransition(.opacity)
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .help(isRequired ? "Klicken und neue Tastenkombination drücken" : "Klicken und Tastenkombination drücken · ⌫ entfernt sie")
        .accessibilityLabel(name.isEmpty ? Text("Tastenkürzel") : Text("Tastenkürzel für \(name)"))
        .accessibilityValue(isRecording ? String(localized: "Warte auf Eingabe") : combination?.displayString ?? String(localized: "Nicht festgelegt"))
        .animation(Theme.spring, value: isRecording)
        .onAppear { if startsRecording { start() } }
        .onDisappear(perform: stop)
        // Another recorder took over, or the panel closed.
        .onChange(of: isRecording) { if !isRecording { removeMonitor() } }
    }

    private func start() {
        removeMonitor()
        model.activeRecorder = id
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                if event.keyCode == 53 { // Esc
                    cancel()
                } else if event.keyCode == 51, !isRequired { // ⌫
                    stop()
                    combination = nil
                } else if let new = HotKey.Combination(event: event) {
                    stop()
                    combination = new
                }
            }
            return nil
        }
    }

    private func cancel() {
        stop()
        onCancel()
    }

    private func stop() {
        if isRecording { model.activeRecorder = nil }
        removeMonitor()
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

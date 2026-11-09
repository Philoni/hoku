import AppKit
import HueKit
import SwiftUI

struct SettingsView: View {
    @Environment(PanelPresentation.self) private var presentation
    @Environment(AppModel.self) private var model
    @Environment(HueStore.self) private var store
    let push: (Route) -> Void
    let pop: () -> Void

    @State private var confirmForget = false

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 10) {
            PageHeader(title: "Einstellungen", onBack: pop) { EmptyView() }

            PageScroll(maxHeight: 440) {
                VStack(spacing: 7) {
                    SectionTitle(text: "Bedienung")
                    VStack(spacing: 10) {
                        Button {
                            push(.shortcuts)
                        } label: {
                            HStack {
                                Label("Tastenkürzel", systemImage: "keyboard")
                                Spacer()
                                Text(shortcutSummary).foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                        Divider().opacity(0.4)
                        SettingSwitch(title: "Beim Anmelden starten", systemImage: "power.circle", isOn: $model.launchesAtLogin)
                        Divider().opacity(0.4)
                        HStack {
                            Label("Erscheinungsbild", systemImage: "circle.lefthalf.filled")
                            Spacer()
                        }
                        FlowChips(
                            options: AppearanceMode.allCases.map { ($0.rawValue, $0.title) },
                            isSelected: { $0 == model.appearance.rawValue },
                            toggle: { model.appearance = AppearanceMode(rawValue: $0) ?? .automatic }
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .padding(12)
                    .background(CardBackground())

                    KeyboardHelp()

                    SectionTitle(text: "Automationen")
                    AwayAutomationCard(automation: $model.awayAutomation)

                    if Features.awayReminder {
                        Button {
                            push(.leftOnReminder)
                        } label: {
                            HStack {
                                Label("Unterwegs-Hinweis", systemImage: "house.and.flag.fill")
                                Spacer()
                                Text(leftOnStatus).foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                            }
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .padding(12)
                            .background(CardBackground())
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                    }

                    Button {
                        push(.routines)
                    } label: {
                        HStack {
                            Label("Wecker & Schlafen gehen", systemImage: "alarm.fill")
                            Spacer()
                            Text("\(store.routines(.wakeUp).count + store.routines(.goToSleep).count)")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                        }
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .padding(12)
                        .background(CardBackground())
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())

                    Button {
                        push(.devices)
                    } label: {
                        let issues = store.deviceIssues.count
                        HStack {
                            Label("Geräte-Check", systemImage: issues == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            Spacer()
                            Text(issues == 0 ? "Alles in Ordnung" : "\(issues) Hinweise")
                                .foregroundStyle(issues == 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                        }
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .padding(12)
                        .background(CardBackground())
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())

                    SectionTitle(text: "Siri")
                    Button {
                        push(.siriCommands)
                    } label: {
                        HStack {
                            Label("Siri-Befehle einrichten", systemImage: "waveform.badge.mic")
                            Spacer()
                            Text("„Zimmer an“").foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                        }
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .padding(12)
                        .background(CardBackground())
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())

                    Button {
                        presentation.openSetup()
                    } label: {
                        HStack {
                            Label("Einrichtung erneut starten", systemImage: "sparkles")
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                        }
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .padding(12)
                        .background(CardBackground())
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())

                    SectionTitle(text: "Für Fortgeschrittene")
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Für eigene Kurzbefehle, Raycast oder Skripte – per „URLs öffnen“:")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                        ForEach(examples, id: \.self) { example in
                            Text(example)
                                .font(.system(size: 10.5, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(CardBackground())

                    SectionTitle(text: "Bridge")
                    VStack(alignment: .leading, spacing: 5) {
                        row("Name", store.credentials?.name ?? "Hue Bridge")
                        row("Adresse", store.credentials?.host ?? "–")
                        row("Status", statusText)
                        row("Inhalt", "\(store.lights.count) Lampen · \(store.rooms.count) Räume · \(store.scenes.count) Szenen")
                    }
                    .padding(12)
                    .background(CardBackground())

                    HStack {
                        Button("Bridge trennen …", role: .destructive) { confirmForget = true }
                            .buttonStyle(.glass)
                        Spacer()
                        Button("Beenden") { NSApplication.shared.terminate(nil) }
                            .buttonStyle(.glass)
                            .keyboardShortcut("q", modifiers: .command)
                    }
                    .controlSize(.small)
                    .padding(.top, 6)
                }
            }
        }
        .confirmationDialog("Bridge trennen?", isPresented: $confirmForget) {
            Button("Trennen", role: .destructive) { model.forgetBridge() }
        } message: {
            Text("Hoku vergisst den Schlüssel. Danach musst du die Link-Taste auf der Bridge erneut drücken.")
        }
    }

    private var examples: [String] {
        let room = store.sortedRooms.first?.name ?? "Wohnzimmer"
        let scene = store.sortedRooms.first.flatMap { store.scenes(in: $0).first?.name } ?? "Entspannen"
        func encode(_ text: String) -> String {
            text.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? text
        }
        return [
            "hoku://szene/\(encode(scene))?raum=\(encode(room))",
            "hoku://raum/\(encode(room))/umschalten",
            "hoku://alle/aus",
        ]
    }

    private var shortcutSummary: String {
        let count = model.shortcuts.count
        return count == 0 ? model.hotKeyCombination.displayString : "\(model.hotKeyCombination.displayString) + \(count)"
    }

    private var leftOnStatus: String {
        if model.leftOn.isEnabled { return "An" }
        return model.cloud.isConnected ? "Aus" : "Einrichten"
    }

    private var statusText: String {
        switch store.connection {
        case .live: "Live verbunden"
        case .connecting: "Verbinde …"
        case .disconnected: "Getrennt"
        case let .offline(reason): "Offline (\(reason))"
        case .unauthorized: "Nicht autorisiert"
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary).frame(width: 62, alignment: .leading)
            Text(value).textSelection(.enabled).lineLimit(2)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11.5, design: .rounded))
    }
}

private struct KeyboardHelp: View {
    private let rows: [(String, String)] = [
        ("↑ ↓", "Raum oder Lampe wählen"),
        ("← →", "Dimmen (mit ⌥ feiner)"),
        ("Leertaste", "An / aus"),
        ("↩", "Öffnen"),
        ("1 – 9", "Szene im Raum starten"),
        ("esc", "Zurück / schließen"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(rows, id: \.0) { key, text in
                HStack {
                    Text(key)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Theme.control))
                        .frame(width: 72, alignment: .leading)
                    Text(text).font(.system(size: 11.5, design: .rounded)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(CardBackground())
    }
}

private struct AwayAutomationCard: View {
    @Environment(HueStore.self) private var store
    @Binding var automation: AwayAutomation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingSwitch(
                title: "Licht aus, wenn ich gehe",
                subtitle: "Beim Sperren, Zuklappen oder Ruhezustand",
                systemImage: "lock.fill",
                isOn: $automation.isEnabled
            )

            if automation.isEnabled {
                FlowChips(
                    options: [("", "Alle Räume")] + (store.sortedRooms + store.sortedZones).map { ($0.id, $0.name) },
                    isSelected: { id in id.isEmpty ? automation.groupIDs.isEmpty : automation.groupIDs.contains(id) },
                    toggle: { id in
                        if id.isEmpty {
                            automation.groupIDs = []
                        } else if let index = automation.groupIDs.firstIndex(of: id) {
                            automation.groupIDs.remove(at: index)
                        } else {
                            automation.groupIDs.append(id)
                        }
                    }
                )
                SettingSwitch(title: "Beim Entsperren wieder an", systemImage: "lock.open.fill", isOn: $automation.restoresOnReturn)
            }
        }
        .font(.system(size: 12.5, weight: .medium, design: .rounded))
        .padding(12)
        .background(CardBackground())
        .animation(Theme.spring, value: automation.isEnabled)
    }
}

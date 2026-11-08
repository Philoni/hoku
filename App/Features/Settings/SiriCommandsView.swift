import HueKit
import SwiftUI

/// Sets up "Hey Siri, Zimmer an"-style commands as personal shortcuts.
struct SiriCommandsView: View {
    @Environment(HueStore.self) private var store
    let pop: () -> Void

    @State private var existing: Set<String> = []
    @State private var selected: Set<String> = []
    @State private var isLoading = true
    @State private var isInstalling = false
    @State private var handedOver = 0
    @State private var message: String?

    var body: some View {
        let commands = SiriCommand.proposals(for: store)
        let pending = commands.filter { selected.contains($0.id) && !existing.contains($0.name.lowercased()) }

        VStack(spacing: 10) {
            PageHeader(title: "Siri-Befehle", subtitle: "„Hey Siri, Zimmer an“ – ohne App-Namen", onBack: pop) {
                EmptyView()
            }

            PageScroll(maxHeight: 400) {
                VStack(spacing: 7) {
                    explanation

                    if isLoading {
                        ProgressView().controlSize(.small).padding(.vertical, 20)
                    } else {
                        ForEach(SiriCommand.Kind.allCases, id: \.self) { kind in
                            let group = commands.filter { $0.kind == kind }
                            if !group.isEmpty {
                                SectionTitle(text: kind.rawValue)
                                FlowChips(
                                    options: group.map { ($0.id, chipTitle($0)) },
                                    isSelected: { id in selected.contains(id) || existing.contains(id.lowercased()) },
                                    toggle: { id in
                                        guard !existing.contains(id.lowercased()) else { return }
                                        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
                                    }
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }

            VStack(spacing: 6) {
                if let message {
                    Text(message)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    install(pending)
                } label: {
                    Label(
                        isInstalling ? "Wird übergeben … \(handedOver)/\(pending.count)" : (pending.isEmpty ? "Alles eingerichtet" : "\(pending.count) Befehle einrichten"),
                        systemImage: pending.isEmpty ? "checkmark" : "waveform.badge.mic"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(pending.isEmpty || isInstalling)
            }
        }
        .task { await reload(commands) }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("So funktioniert’s", systemImage: "info.circle")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            Text("Hoku legt für jeden Befehl einen Kurzbefehl an. Siri führt Kurzbefehle direkt über ihren Namen aus – auch vor Apple Home. Die Kurzbefehle-App fragt pro Befehl einmal nach: „Kurzbefehl hinzufügen“ klicken. Beim ersten Benutzen fragt macOS je Befehl einmal, ob er Hoku öffnen darf – dauerhaft erlauben, dann nie wieder. Danach kannst du sie auch ins Kontrollzentrum oder die Menüleiste legen. ✦ = Sprechvariante, so wie Siri den Namen versteht (z. B. „Light Strip“ für „Lightstrip“).")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(CardBackground())
    }

    private func chipTitle(_ command: SiriCommand) -> String {
        let title = command.aliasOf == nil ? command.name : "\(command.name) ✦"
        return existing.contains(command.name.lowercased()) ? "✓ \(title)" : title
    }

    private func reload(_ commands: [SiriCommand]) async {
        existing = await SiriCommands.existingShortcutNames()
        if selected.isEmpty {
            let recommended = Set(commands.filter(\.isRecommended).map(\.id))
            selected = Set(commands.filter { command in
                guard !existing.contains(command.name.lowercased()) else { return false }
                // Spoken variants come along when their command is set up or recommended.
                if let base = command.aliasOf {
                    return existing.contains(base.lowercased()) || recommended.contains(base)
                }
                return command.isRecommended
            }.map(\.id))
        }
        isLoading = false
    }

    private func install(_ commands: [SiriCommand]) {
        isInstalling = true
        handedOver = 0
        message = "Die Kurzbefehle-App öffnet sich gleich – bitte bei jedem Befehl „Kurzbefehl hinzufügen“ klicken."
        Task {
            do {
                try await SiriCommands.install(commands) { count in handedOver = count }
                message = "Fertig übergeben. Sag zum Beispiel „Hey Siri, \(commands.first?.name ?? "Zimmer an")“."
            } catch {
                message = error.localizedDescription
            }
            isInstalling = false
            // The user adds them in the Shortcuts app; check again a little later.
            try? await Task.sleep(for: .seconds(8))
            existing = await SiriCommands.existingShortcutNames()
            selected = selected.filter { !existing.contains($0.lowercased()) }
        }
    }
}

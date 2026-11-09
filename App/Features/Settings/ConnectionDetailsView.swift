import HueKit
import SwiftUI

/// The technical side of the bridge connection, for people who want to see it or
/// set the address themselves.
struct ConnectionDetailsView: View {
    @Environment(AppModel.self) private var model
    @Environment(HueStore.self) private var store
    let pop: () -> Void

    @State private var config: BridgeConfig?
    @State private var host = ""
    @State private var isChecking = false
    @State private var message: String?
    @State private var didChange = false

    var body: some View {
        VStack(spacing: 10) {
            PageHeader(title: String(localized: "Verbindung"), onBack: pop) { EmptyView() }

            PageScroll(maxHeight: 440) {
                VStack(spacing: 7) {
                    card {
                        row("Status", store.connection.title)
                        row("Adresse", store.credentials?.host ?? "–")
                        row("Bridge-ID", store.credentials?.bridgeID ?? "–")
                        row("Abgleich", lastSync)
                    }

                    SectionTitle(text: String(localized: "Bridge"))
                    card {
                        row("Modell", config?.modelID ?? "…")
                        row("Software", config?.swVersion ?? "…")
                        row("API", config?.apiVersion ?? "…")
                    }

                    SectionTitle(text: String(localized: "Sicherheit"))
                    card {
                        row("Weg", String(localized: "Direkt im lokalen Netzwerk, verschlüsselt (HTTPS)"))
                        row("Zertifikat", String(localized: "Von Signify ausgestellt und an diese Bridge gebunden"))
                        row("Schlüssel", String(localized: "Nur auf diesem Mac gespeichert"))
                    }

                    SectionTitle(text: String(localized: "Adresse von Hand"))
                    card {
                        Text("Hoku findet die Bridge selbst wieder, wenn sich ihre Adresse ändert. Du kannst sie hier auch fest eintragen.")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 8) {
                            TextField("IP-Adresse", text: $host)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12.5, design: .monospaced))
                                .padding(.horizontal, 9)
                                .frame(height: 26)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.control))
                                .onSubmit(apply)
                            Button(isChecking ? "Prüfe …" : "Übernehmen", action: apply)
                                .buttonStyle(.glass)
                                .controlSize(.small)
                                .disabled(isChecking || host.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        if let message {
                            Label(message, systemImage: didChange ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(didChange ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .transition(.blurReplace)
                        }
                    }
                }
            }
        }
        .animation(Theme.spring, value: message)
        .task {
            host = store.credentials?.host ?? ""
            guard !Snapshot.isDemo, let current = store.credentials?.host else { return }
            config = try? await store.client.config(host: current)
        }
    }

    private var lastSync: String {
        guard let date = store.lastSync else { return "–" }
        return date.formatted(.relative(presentation: .named))
    }

    private func apply() {
        guard !isChecking else { return }
        isChecking = true
        message = nil
        Task {
            let error = await model.changeBridgeHost(to: host)
            didChange = error == nil
            message = error ?? String(localized: "Adresse übernommen.")
            isChecking = false
        }
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary).frame(width: 74, alignment: .leading)
            Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11.5, design: .rounded))
    }

    private func card(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6, content: content)
            .padding(12)
            .background(CardBackground())
    }
}

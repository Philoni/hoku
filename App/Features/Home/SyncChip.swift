import HueKit
import SwiftUI

/// "Sync läuft · Musik": a sync app is streaming to these lights, so nothing Hoku
/// sends them sticks. Says why, and offers to end it.
struct SyncChip: View {
    @Environment(HueStore.self) private var store
    let area: EntertainmentArea

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .symbolEffect(.variableColor.iterative, options: .repeating)
            Text("\(Text("Sync läuft").fontWeight(.semibold))\(Text(" · \(area.name)").foregroundStyle(.secondary))")
                .font(.system(size: 11.5, design: .rounded))
                .lineLimit(1)
            Spacer(minLength: 0)
            Button("Sync beenden") {
                Haptics.tap()
                store.stopStreaming(area)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .help("Beendet die Synchronisierung. Danach steuerst du die Lampen wieder wie gewohnt.")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(Capsule().fill(Theme.tile))
        .overlay(Capsule().strokeBorder(Theme.tileStroke, lineWidth: 1))
        .help("Eine Sync-App (z. B. Hue Sync) steuert gerade die Lampen in „\(area.name)“. Solange reagieren sie nicht auf Hoku.")
        .accessibilityElement(children: .combine)
    }
}

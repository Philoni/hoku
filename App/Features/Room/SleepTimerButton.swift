import HueKit
import SwiftUI

/// Fade the room out over a while, e.g. to fall asleep. Runs on the bridge.
struct SleepTimerButton: View {
    @Environment(HueStore.self) private var store
    let group: HueGroup
    let isOn: Bool
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        if isSnapshot {
            // Menus are AppKit-backed and don't render offscreen; show the look instead.
            CircleIconButton(title: "Einschlaf-Timer", systemImage: "moon.zzz.fill") {}
        } else if let fadeOut = store.fadeOuts[group.id] {
            Button {
                Haptics.tap()
                store.cancelFadeOut(group)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "moon.zzz.fill")
                    Text(fadeOut.ends, style: .timer).monospacedDigit()
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).opacity(0.7)
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 4)
            }
            .buttonStyle(.glass)
            .help("Einschlaf-Timer abbrechen")
            .transition(.blurReplace)
        } else {
            Menu {
                Section("Langsam ausdimmen in …") {
                    ForEach([15, 30, 45, 60, 90], id: \.self) { minutes in
                        Button("\(minutes) Minuten") { store.startFadeOut(group, minutes: minutes) }
                    }
                }
            } label: {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 12, weight: .semibold))
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .fixedSize()
            .disabled(!isOn)
            .help("Einschlaf-Timer")
        }
    }
}

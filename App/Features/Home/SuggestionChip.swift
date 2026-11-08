import HueKit
import SwiftUI

/// "Nachtlicht · Zimmer" — a habit Hoku has learned; one click and it's on.
/// Deliberately quiet: no shimmer, no breathing, just a tint of the scene's colors.
struct SuggestionChip: View {
    @Environment(HueStore.self) private var store
    let scene: HueScene
    let group: HueGroup
    var isLearned = false

    var body: some View {
        let colors = scene.displayColors
        Button {
            Haptics.tap()
            store.recall(scene)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(AngularGradient(colors: colors + [colors[0]], center: .center))
                    .frame(width: 12, height: 12)
                Text("\(Text(scene.name).fontWeight(.semibold))\(Text(" · \(group.name)").foregroundStyle(.secondary))")
                    .font(.system(size: 11.5, design: .rounded))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background {
                Capsule().fill(Theme.tile)
                Capsule().fill(LinearGradient(colors: colors.map { $0.opacity(0.1) }, startPoint: .leading, endPoint: .trailing))
            }
            .overlay(Capsule().strokeBorder(Theme.tileStroke, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .help(isLearned
            ? "Das machst du um diese Zeit oft: \(scene.name) im Raum \(group.name)"
            : "Vorschlag für jetzt: \(scene.name) im Raum \(group.name)")
    }
}

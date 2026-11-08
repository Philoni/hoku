import HueKit
import SwiftUI

/// Tempo of the running dynamic scene; applies live.
struct SpeedCard: View {
    @Environment(HueStore.self) private var store
    let scene: HueScene
    @State private var dragSpeed: Double?

    var body: some View {
        let speed = dragSpeed ?? scene.speed ?? 0.5
        let colors = scene.displayColors.gradientStops

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("\(scene.name) · dynamisch", systemImage: "waveform")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .symbolEffect(.variableColor.iterative.reversing)
                    .lineLimit(1)
                Spacer()
                Button("Anhalten", systemImage: "pause.fill") {
                    Haptics.tap()
                    store.recall(scene, as: .static)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .help("Dynamik anhalten")
            }
            HStack(spacing: 10) {
                Image(systemName: "tortoise.fill").foregroundStyle(.secondary)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.control)
                        Capsule()
                            .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(10, geometry.size.width * speed))
                    }
                    .contentShape(Capsule())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                let value = min(max(gesture.location.x / geometry.size.width, 0), 1)
                                dragSpeed = value
                                store.setSpeed(value, scene: scene)
                            }
                            .onEnded { _ in dragSpeed = nil }
                    )
                }
                .frame(height: 10)
                Image(systemName: "hare.fill").foregroundStyle(.secondary)
            }
            .font(.system(size: 10.5))
        }
        .padding(11)
        .background(CardBackground(tint: colors.first))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tempo der dynamischen Szene")
    }
}

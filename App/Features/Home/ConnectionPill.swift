import HueKit
import SwiftUI

/// Only shows up when something is off; a healthy connection stays invisible.
struct ConnectionPill: View {
    @Environment(HueStore.self) private var store
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch store.connection {
            case .live, .disconnected:
                EmptyView()
            case .connecting where !store.lights.isEmpty:
                EmptyView()
            case .connecting:
                pill("Verbinde mit der Bridge …", systemImage: "antenna.radiowaves.left.and.right", color: .secondary)
            case .offline:
                pill("Bridge gerade nicht erreichbar", systemImage: "wifi.exclamationmark", color: .orange) {
                    Button("Erneut") { store.reconnect() }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
            case .unauthorized:
                pill("Hoku ist nicht mehr gekoppelt", systemImage: "key.slash", color: .red) {
                    Button("Koppeln") { model.forgetBridge() }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
            }
        }
        .transition(.move(edge: .top).combined(with: .blurReplace))
        .animation(Theme.spring, value: store.connection)
    }

    private func pill(
        _ text: String,
        systemImage: String,
        color: Color,
        @ViewBuilder action: () -> some View = { EmptyView() }
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .symbolEffect(.pulse)
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .lineLimit(1)
            Spacer(minLength: 0)
            action()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
    }
}

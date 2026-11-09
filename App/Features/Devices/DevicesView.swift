import HueKit
import SwiftUI

/// Batteries, reachability and firmware of every Hue device at a glance.
struct DevicesView: View {
    @Environment(HueStore.self) private var store
    let pop: () -> Void

    var body: some View {
        let issues = store.deviceIssues
        let devices = store.sortedDevices

        VStack(spacing: 10) {
            PageHeader(title: String(localized: "Geräte"), subtitle: String(localized: "\(devices.count) Geräte an deiner Bridge"), onBack: pop) { EmptyView() }

            PageScroll(maxHeight: 440) {
                VStack(spacing: 7) {
                    HealthSummary(issueCount: issues.count)

                    SectionTitle(text: String(localized: "Lampen & Steckdosen"))
                    ForEach(Array(devices.filter { !$0.lightIDs.isEmpty }.enumerated()), id: \.element.id) { index, device in
                        DeviceRow(device: device).staggered(index)
                    }

                    let others = devices.filter(\.lightIDs.isEmpty)
                    if !others.isEmpty {
                        SectionTitle(text: String(localized: "Schalter & Sensoren"))
                        ForEach(others) { device in
                            DeviceRow(device: device)
                        }
                    }
                }
            }
        }
    }
}

private struct HealthSummary: View {
    let issueCount: Int

    var body: some View {
        let isHealthy = issueCount == 0
        HStack(spacing: 12) {
            Image(systemName: isHealthy ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 26))
                .foregroundStyle(isHealthy ? AnyShapeStyle(Color.green.gradient) : AnyShapeStyle(Color.orange.gradient))
                .symbolEffect(.bounce, value: issueCount)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(isHealthy ? "Alles in Ordnung" : "\(issueCount) \(issueCount == 1 ? String(localized: "Hinweis") : String(localized: "Hinweise"))")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(isHealthy ? "Alle Geräte erreichbar, Batterien voll, Firmware aktuell." : "Details stehen bei den Geräten unten.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(CardBackground(tint: isHealthy ? .green : .orange))
    }
}

private struct DeviceRow: View {
    @Environment(HueStore.self) private var store
    let device: Device

    var body: some View {
        let health = store.health(of: device)
        let light = device.lightIDs.first.flatMap { store.lights[$0] }
        let icon = light.map { Icons.light(store.archetype(of: $0), dimmable: $0.supportsDimming) } ?? "switch.2"

        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 22)
                .foregroundStyle(health.isConnected ? AnyShapeStyle(Theme.text) : AnyShapeStyle(Color.red))
            VStack(alignment: .leading, spacing: 1) {
                Text(device.metadata?.name ?? String(localized: "Gerät"))
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text([store.room(of: device)?.name, device.productData?.productName].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)

            if health.hasUpdate {
                Badge(text: String(localized: "Update"), systemImage: "arrow.down.circle.fill", color: .blue)
            }
            if let level = health.batteryLevel {
                Badge(text: "\(level) %", systemImage: batterySymbol(level), color: level <= 20 ? .orange : .green)
            }
            if !health.isConnected {
                Badge(text: String(localized: "Nicht erreichbar"), systemImage: "wifi.slash", color: .red)
            } else {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                    .shadow(color: .green.opacity(0.8), radius: 3)
                    .help("Erreichbar")
                    .accessibilityLabel("Erreichbar")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(CardBackground())
        .accessibilityElement(children: .combine)
    }

    private func batterySymbol(_ level: Int) -> String {
        switch level {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }
}

private struct Badge: View {
    let text: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}

/// Shown on the home page only when a device needs attention.
struct DeviceIssueChip: View {
    @Environment(HueStore.self) private var store
    let issues: [DeviceIssue]
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .symbolEffect(.pulse)
                    .accessibilityHidden(true)
                Text(summary)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.faint)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.orange.opacity(0.16)))
            .overlay(Capsule().strokeBorder(Color.orange.opacity(0.3), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }

    private var summary: String {
        guard issues.count == 1, let issue = issues.first else { return String(localized: "\(issues.count) Geräte brauchen Aufmerksamkeit") }
        let name = store.devices[issue.deviceID]?.metadata?.name ?? String(localized: "Gerät")
        switch issue.kind {
        case let .battery(level, _): return String(localized: "\(name): Batterie \(level.map { "\($0) %" } ?? String(localized: "schwach"))")
        case .unreachable: return String(localized: "\(name) ist nicht erreichbar")
        case .update: return String(localized: "\(name): Firmware-Update verfügbar")
        }
    }
}

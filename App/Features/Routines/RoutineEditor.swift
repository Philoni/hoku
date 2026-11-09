import HueKit
import SwiftUI

struct RoutineEditor: View {
    @Environment(HueStore.self) private var store
    let kind: RoutineKind
    let routine: BehaviorInstance?
    let done: () -> Void

    @State private var draft = RoutineDraft(name: "", hour: 7, minute: 0, weekdays: [], groupID: "", fadeMinutes: 15, endBrightness: 100)
    @State private var isSaving = false
    @State private var error: String?
    @State private var confirmDelete = false

    var body: some View {
        VStack(spacing: 10) {
            PageHeader(title: routine == nil ? (kind == .wakeUp ? String(localized: "Neuer Wecker") : String(localized: "Neue Routine")) : draft.name, onBack: done) {
                Button(isSaving ? "…" : "Sichern") { save() }
                    .buttonStyle(.glassProminent)
                    .controlSize(.small)
                    .disabled(isSaving || draft.groupID.isEmpty || draft.name.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }

            PageScroll(maxHeight: 440) {
                VStack(spacing: 8) {
                    // Time, large and central — the thing that matters most.
                    HStack(spacing: 4) {
                        TimeWheel(value: $draft.hour, range: 0...23)
                        Text(":").font(.system(size: 34, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                        TimeWheel(value: $draft.minute, range: 0...59, step: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(CardBackground(tint: kind == .wakeUp ? .orange : .indigo))

                    LightCurvePreview(
                        isSunrise: kind == .wakeUp,
                        roomName: store.group(draft.groupID)?.name ?? String(localized: "Raum"),
                        roomIcon: Icons.room(store.group(draft.groupID)?.metadata?.archetype),
                        fadeMinutes: draft.fadeMinutes,
                        endBrightness: kind == .wakeUp ? draft.endBrightness : 0
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Name", text: $draft.name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Divider().opacity(0.4)
                        FlowChips(
                            options: RoutineDraft.weekdayOrder.map { ($0, Weekdays.short[$0] ?? $0) },
                            isSelected: { draft.weekdays.contains($0) },
                            toggle: { day in
                                if let index = draft.weekdays.firstIndex(of: day) {
                                    draft.weekdays.remove(at: index)
                                } else {
                                    draft.weekdays.append(day)
                                    draft.weekdays.sort { RoutineDraft.weekdayOrder.firstIndex(of: $0)! < RoutineDraft.weekdayOrder.firstIndex(of: $1)! }
                                }
                            }
                        )
                        Text(draft.weekdays.isEmpty ? String(localized: "Ohne Wochentag: einmalig") : Weekdays.summary(draft.weekdays))
                            .font(.system(size: 10.5, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(CardBackground())

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Raum").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                        FlowChips(
                            options: (store.sortedRooms + store.sortedZones).map { ($0.id, $0.name) },
                            isSelected: { draft.groupID == $0 },
                            toggle: { draft.groupID = $0 }
                        )
                        Divider().opacity(0.4)
                        Text(kind == .wakeUp ? "Sonnenaufgang über" : "Ausdimmen über")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        FlowChips(
                            options: [5, 10, 15, 20, 30, 45, 60].map { ("\($0)", String(localized: "\($0) Min.")) },
                            isSelected: { $0 == "\(draft.fadeMinutes)" },
                            toggle: { draft.fadeMinutes = Int($0) ?? 15 }
                        )
                        if kind == .wakeUp {
                            Divider().opacity(0.4)
                            HStack {
                                Text("Endhelligkeit").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(draft.endBrightness)) %").font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                            }
                            Slider(value: $draft.endBrightness, in: 10...100, step: 5)
                                .controlSize(.small)
                                .tint(.orange)
                        }
                    }
                    .padding(12)
                    .background(CardBackground())

                    if let error {
                        Text(error).font(.system(size: 11, design: .rounded)).foregroundStyle(.orange)
                    }

                    if routine != nil {
                        Button("Löschen", role: .destructive) { confirmDelete = true }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                            .padding(.top, 4)
                    }
                }
            }
        }
        .onAppear(perform: load)
        .confirmationDialog("„\(draft.name)“ löschen?", isPresented: $confirmDelete) {
            Button("Löschen", role: .destructive) { delete() }
        } message: {
            Text("Die Automation wird auch aus der Hue-App entfernt.")
        }
    }

    private func load() {
        if let routine {
            draft = store.draft(from: routine)
        } else {
            draft.name = kind == .wakeUp ? String(localized: "Aufwachen") : String(localized: "Schlafen gehen")
            draft.hour = kind == .wakeUp ? 7 : 23
            draft.weekdays = Array(RoutineDraft.weekdayOrder.prefix(5))
            draft.groupID = store.sortedRooms.first?.id ?? ""
        }
    }

    private func save() {
        isSaving = true
        error = nil
        Task {
            do {
                if let routine {
                    try await store.save(draft, to: routine)
                } else {
                    try await store.create(draft, kind: kind)
                }
                Haptics.tap()
                done()
            } catch {
                self.error = error.localizedDescription
            }
            isSaving = false
        }
    }

    private func delete() {
        guard let routine else { return }
        Task {
            do {
                try await store.delete(routine)
                done()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Big number you change by scrolling, dragging or clicking the arrows.
private struct TimeWheel: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1

    var body: some View {
        VStack(spacing: 0) {
            Button { change(+step) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            Text(String(format: "%02d", value))
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
                .frame(width: 66)
            Button { change(-step) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 12, weight: .bold))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { gesture in
                    // Drag up/down; every 14 points is one step.
                    let steps = Int(-gesture.translation.height / 14)
                    if steps != 0, abs(steps) > lastSteps.magnitude {
                        change(steps > 0 ? step : -step)
                        lastSteps = steps
                    }
                }
                .onEnded { _ in lastSteps = 0 }
        )
    }

    @State private var lastSteps = 0

    private func change(_ delta: Int) {
        withAnimation(Theme.spring) {
            let count = range.upperBound - range.lowerBound + 1
            let next = ((value - range.lowerBound + delta) % count + count) % count + range.lowerBound
            // Snap minutes to the step grid when stepping.
            value = step > 1 ? (next / step) * step : next
        }
        Haptics.edge()
    }
}

/// The room card playing the routine's light in fast-forward: a sunrise from deep red
/// to warm white, or the evening fade back into the dark. Replays whenever the room,
/// duration or brightness changes, and on click. Only a preview — no lamp is switched.
private struct LightCurvePreview: View {
    let isSunrise: Bool
    let roomName: String
    let roomIcon: String
    let fadeMinutes: Int
    /// Brightness at the end of a wake-up, in percent.
    let endBrightness: Double

    @State private var replay = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)

        KeyframeAnimator(initialValue: isSunrise ? 1.0 : 0.0, trigger: replay) { progress in
            let level = isSunrise ? progress * max(endBrightness, 10) / 100 : 1 - progress
            let color = Self.color(at: isSunrise ? progress : 1 - progress * 0.8)
            ZStack(alignment: .leading) {
                shape.fill(Theme.tile)
                // The sky over the room: brightens from the horizon up.
                LinearGradient(colors: [color, color.opacity(0.35)], startPoint: .bottom, endPoint: .top)
                    .opacity(0.08 + 0.85 * level)
                // The sun, rising on the right (or setting).
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.95), color, color.opacity(0)], center: .center, startRadius: 0, endRadius: 22))
                    .frame(width: 44, height: 44)
                    .offset(x: 190, y: 30 - 34 * level)
                    .opacity(0.25 + 0.75 * level)
                HStack(spacing: 10) {
                    Image(systemName: roomIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(roomName)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text("Vorschau · \(fadeMinutes) Min. in 3 Sek.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .opacity(0.7)
                    }
                    Spacer()
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .opacity(0.6)
                }
                .foregroundStyle(level > 0.55 ? AnyShapeStyle(.black.opacity(0.75)) : AnyShapeStyle(Theme.text))
                .padding(.horizontal, 12)
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.tileStroke, lineWidth: 1))
            .shadow(color: color.opacity(0.35 * level), radius: 10, y: 2)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(0.0, duration: 0.01)
                CubicKeyframe(0.0, duration: 0.25)
                CubicKeyframe(1.0, duration: 2.8)
            }
        }
        .frame(height: 50)
        .contentShape(shape)
        .onTapGesture {
            Haptics.tap()
            replay += 1
        }
        .help("Zeitraffer abspielen")
        .task(id: "\(roomName)-\(fadeMinutes)-\(Int(endBrightness))") {
            // Let rapid changes settle before replaying.
            try? await Task.sleep(for: .milliseconds(350))
            if !Task.isCancelled { replay += 1 }
        }
    }

    /// Night red → dawn orange → warm daylight.
    static func color(at progress: Double) -> Color {
        let night = Color(red: 0.42, green: 0.07, blue: 0.06)
        let dawn = Color(red: 1, green: 0.46, blue: 0.16)
        let day = Color(red: 1, green: 0.87, blue: 0.64)
        let p = min(max(progress, 0), 1)
        return p < 0.5 ? night.mix(with: dawn, by: p * 2) : dawn.mix(with: day, by: (p - 0.5) * 2)
    }
}

import HueKit
import SwiftUI

/// Wake-ups and go-to-sleep routines stored on the bridge (the same ones the Hue
/// app shows under Automations). They run on the bridge, even with the Mac asleep.
struct RoutinesView: View {
    @Environment(HueStore.self) private var store
    let pop: () -> Void

    private enum Editing: Equatable {
        case existing(BehaviorInstance)
        case new(RoutineKind)
    }

    @State private var editing: Editing?

    init(pop: @escaping () -> Void, newRoutine: RoutineKind? = nil) {
        self.pop = pop
        _editing = State(initialValue: newRoutine.map { .new($0) })
    }

    var body: some View {
        VStack(spacing: 10) {
            switch editing {
            case let .existing(routine):
                RoutineEditor(kind: store.kind(of: routine) ?? .wakeUp, routine: routine) { editing = nil }
                    .transition(.push(from: .trailing))
            case let .new(kind):
                RoutineEditor(kind: kind, routine: nil) { editing = nil }
                    .transition(.push(from: .trailing))
            case nil:
                list.transition(.push(from: .leading))
            }
        }
        .animation(Theme.softSpring, value: editing)
    }

    private var list: some View {
        VStack(spacing: 10) {
            PageHeader(title: String(localized: "Wecker & Schlafen"), subtitle: String(localized: "Läuft auf der Bridge, auch wenn der Mac schläft"), onBack: pop) {
                EmptyView()
            }

            PageScroll(maxHeight: 420) {
                VStack(spacing: 7) {
                    section(.wakeUp, title: String(localized: "Lichtwecker"), icon: "sunrise.fill", empty: String(localized: "Wach mit einem sanften Sonnenaufgang auf."))
                    section(.goToSleep, title: String(localized: "Schlafen gehen"), icon: "moon.stars.fill", empty: String(localized: "Licht dimmt abends langsam herunter."))
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ kind: RoutineKind, title: String, icon: String, empty: String) -> some View {
        let routines = store.routines(kind)
        HStack {
            SectionTitle(text: title)
            Button {
                editing = .new(kind)
            } label: {
                Image(systemName: "plus").font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .help("\(title) hinzufügen")
        }
        if routines.isEmpty {
            Label(empty, systemImage: icon)
                .font(.system(size: 11.5, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(CardBackground())
        }
        ForEach(Array(routines.enumerated()), id: \.element.id) { index, routine in
            RoutineCard(routine: routine, kind: kind) { editing = .existing(routine) }
                .staggered(index)
        }
    }
}

private struct RoutineCard: View {
    @Environment(HueStore.self) private var store
    let routine: BehaviorInstance
    let kind: RoutineKind
    let open: () -> Void

    var body: some View {
        let colors: [Color] = kind == .wakeUp
            ? [Color(red: 1, green: 0.55, blue: 0.2), Color(red: 1, green: 0.85, blue: 0.5)]
            : [Color(red: 0.35, green: 0.25, blue: 0.7), Color(red: 0.95, green: 0.45, blue: 0.3)]

        HStack(spacing: 12) {
            Button(action: open) {
                HStack(spacing: 12) {
                    Text(timeText)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(routine.enabled ? AnyShapeStyle(Theme.text) : AnyShapeStyle(.secondary))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(routine.name).font(.system(size: 12.5, weight: .semibold, design: .rounded)).lineLimit(1)
                        Text(detailText).font(.system(size: 10.5, design: .rounded)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            GlowSwitch(isOn: routine.enabled, tint: colors[0]) {
                store.setEnabled(!routine.enabled, routine: routine)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            ZStack {
                CardBackground()
                if routine.enabled {
                    LinearGradient(colors: colors.map { $0.opacity(0.28) }, startPoint: .leading, endPoint: .trailing)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                }
            }
        }
        .animation(Theme.spring, value: routine.enabled)
    }

    private var timeText: String {
        String(format: "%02d:%02d", routine.hour ?? 0, routine.minute ?? 0)
    }

    private var detailText: String {
        let room = routine.groupIDs.compactMap { store.group($0)?.name }.joined(separator: ", ")
        return [Weekdays.summary(routine.weekdays), room].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

enum Weekdays {
    static let short: [String: String] = [
        "monday": String(localized: "Mo"), "tuesday": String(localized: "Di"), "wednesday": String(localized: "Mi"), "thursday": String(localized: "Do"),
        "friday": String(localized: "Fr"), "saturday": String(localized: "Sa"), "sunday": String(localized: "So"),
    ]

    static func summary(_ days: [String]) -> String {
        let set = Set(days)
        if set.count == 7 { return String(localized: "Täglich") }
        if set == Set(RoutineDraft.weekdayOrder.prefix(5)) { return String(localized: "Werktags") }
        if set == ["saturday", "sunday"] { return String(localized: "Wochenende") }
        if set.isEmpty { return String(localized: "Einmalig") }
        return RoutineDraft.weekdayOrder.filter(set.contains).compactMap { short[$0] }.joined(separator: ", ")
    }
}

import HueKit
import SwiftUI

/// Pin rooms and zones to the top and put them in your own order.
struct RoomOrderView: View {
    @Environment(AppModel.self) private var model
    @Environment(HueStore.self) private var store
    let pop: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            PageHeader(title: String(localized: "Räume ordnen"), onBack: pop) { EmptyView() }

            PageScroll(maxHeight: 440) {
                VStack(spacing: 7) {
                    Text("Angeheftete stehen oben. Die Reihenfolge gilt überall in Hoku.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)

                    section(String(localized: "Räume"), groups: store.sortedRooms, all: Array(store.rooms.values))
                    section(String(localized: "Zonen"), groups: store.topLevelZones, all: store.topLevelZones)

                    if store.groupOrder.isCustom {
                        Button("Nach Name sortieren") {
                            Haptics.tap()
                            withAnimation(Theme.spring) { model.updateGroupOrder { $0 = GroupOrder() } }
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                        .transition(.blurReplace)
                    }
                }
            }
        }
        .animation(Theme.spring, value: store.groupOrder)
    }

    @ViewBuilder
    private func section(_ title: String, groups: [HueGroup], all: [HueGroup]) -> some View {
        if !groups.isEmpty {
            SectionTitle(text: title)
            VStack(spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    if index > 0 { Divider().opacity(0.4) }
                    row(group, all: all)
                }
            }
            .padding(.horizontal, 12)
            .background(CardBackground())
        }
    }

    private func row(_ group: HueGroup, all: [HueGroup]) -> some View {
        let order = store.groupOrder
        let isPinned = order.pinned.contains(group.id)
        return HStack(spacing: 6) {
            Image(systemName: Icons.room(group.metadata?.archetype)).frame(width: 22)
            Text(group.name).lineLimit(1)
            Spacer(minLength: 4)
            iconButton(
                isPinned ? String(localized: "\(group.name) lösen") : String(localized: "\(group.name) anheften"),
                systemImage: isPinned ? "pin.fill" : "pin"
            ) {
                model.updateGroupOrder { $0.togglePin(group.id) }
            }
            .foregroundStyle(isPinned ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
            iconButton(String(localized: "\(group.name) nach oben"), systemImage: "chevron.up") {
                model.updateGroupOrder { $0.move(group.id, up: true, in: all) }
            }
            .disabled(!order.canMove(group.id, up: true, in: all))
            .opacity(order.canMove(group.id, up: true, in: all) ? 1 : 0.3)
            iconButton(String(localized: "\(group.name) nach unten"), systemImage: "chevron.down") {
                model.updateGroupOrder { $0.move(group.id, up: false, in: all) }
            }
            .disabled(!order.canMove(group.id, up: false, in: all))
            .opacity(order.canMove(group.id, up: false, in: all) ? 1 : 0.3)
        }
        .font(.system(size: 12.5, weight: .medium, design: .rounded))
        .padding(.vertical, 8)
    }

    private func iconButton(_ label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            withAnimation(Theme.spring) { action() }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 22)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.control))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
        .help(label)
    }
}

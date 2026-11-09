import HueKit
import SwiftUI

struct HomeView: View {
    @Environment(HueStore.self) private var store
    @Environment(AppModel.self) private var model
    @Environment(PanelPresentation.self) private var presentation
    let push: (Route) -> Void
    @State private var selection: Int?

    init(push: @escaping (Route) -> Void, selection: Int? = nil) {
        self.push = push
        _selection = State(initialValue: selection)
    }
    /// True for a moment after "all off", so the cards go dark one after another.
    @State private var isCascading = false
    /// Rooms and lamps that were on when "all off" was pressed: only they glow out.
    @State private var coolingIDs: Set<String> = []
    @State private var phase = DayPhase.now

    var body: some View {
        let rooms = store.sortedRooms
        let zones = store.topLevelZones
        let items = rooms + zones
        let suggestion = model.suggestion(for: phase)

        VStack(spacing: 10) {
            header
            ConnectionPill()
            let issues = store.deviceIssues
            if !issues.isEmpty {
                DeviceIssueChip(issues: issues) { push(.devices) }
                    .transition(.blurReplace)
            }
            ForEach(store.streamingAreas) { area in
                SyncChip(area: area)
                    .transition(.blurReplace)
            }
            // Only a habit Hoku has actually learned, and only while the light differs.
            if let suggestion, suggestion.isLearned {
                SuggestionChip(scene: suggestion.scene, group: suggestion.group, isLearned: true)
                    .id(suggestion.scene.id)
                    .transition(.blurReplace)
            }

            ScrollViewReader { proxy in
                PageScroll {
                    VStack(spacing: 7) {
                        if !rooms.isEmpty {
                            SectionTitle(text: String(localized: "Räume"))
                            ForEach(Array(rooms.enumerated()), id: \.element.id) { index, group in
                                card(for: group, index: index)
                                    .selectionRing(selection == index)
                                    .id(group.id)
                                    .staggered(index)
                            }
                        }
                        if !zones.isEmpty {
                            SectionTitle(text: String(localized: "Zonen")).padding(.top, 8)
                            ForEach(Array(zones.enumerated()), id: \.element.id) { index, group in
                                card(for: group, index: rooms.count + index)
                                    .selectionRing(selection == rooms.count + index)
                                    .id(group.id)
                                    .staggered(rooms.count + index)
                            }
                        }
                        if rooms.isEmpty && zones.isEmpty {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.vertical, 40)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .onChange(of: selection) {
                    guard let selection, items.indices.contains(selection) else { return }
                    withAnimation(Theme.spring) { proxy.scrollTo(items[selection].id) }
                }
                .onChange(of: presentation.expandedRoomID) {
                    // Bring the opened card's lamps into view if they unfold below the fold.
                    guard let expandedID = presentation.expandedRoomID else { return }
                    Task {
                        try? await Task.sleep(for: .milliseconds(120))
                        withAnimation(Theme.softSpring) { proxy.scrollTo(expandedID) }
                    }
                }
            }
        }
        .animation(Theme.spring, value: store.streamingAreas)
        .keyboardNavigation(
            count: items.count,
            selection: $selection,
            onToggle: { index in
                let group = items[index]
                store.setOn(!(store.groupedLight(for: group)?.isOn ?? false), group: group)
            },
            onAdjust: { index, delta in store.adjustBrightness(by: delta, group: items[index]) },
            onOpen: { index in open(items[index]) }
        )
    }

    private func card(for group: HueGroup, index: Int) -> some View {
        GroupCard(
            group: group,
            animationDelay: isCascading ? Double(index) * 0.09 : 0,
            coolingIDs: coolingIDs,
            isExpanded: presentation.expandedRoomID == group.id,
            onExpand: {
                withAnimation(Theme.spring) {
                    presentation.expandedRoomID = presentation.expandedRoomID == group.id ? nil : group.id
                }
            }
        ) { open(group) }
    }

    /// Opens the room's page; coming back, the card is found unfolded, so the
    /// lamps just visited are one glance away instead of one more click.
    private func open(_ group: HueGroup) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { presentation.expandedRoomID = group.id }
        push(.group(group.id))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 6) {
            // The cards already show what's on; the greeting needs no count.
            Text(phase.greeting)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .contentTransition(.opacity)
                .lineLimit(1)
            Spacer(minLength: 4)
            CircleIconButton(title: String(localized: "Wecker & Routinen"), systemImage: "alarm.fill", diameter: 22) { push(.routines) }

            CircleIconButton(title: String(localized: "Alle Lichter ausschalten"), systemImage: "power", diameter: 22) {
                Haptics.tap()
                let groups = store.sortedRooms + store.topLevelZones
                let duration = 1.6 + Double(groups.count) * 0.09
                coolingIDs = Set(groups.filter { store.groupedLight(for: $0)?.isOn == true }.map(\.id))
                    .union(store.lights.values.filter(\.isOn).map(\.id))
                isCascading = true
                store.setAllOff()
                Task {
                    try? await Task.sleep(for: .seconds(duration))
                    isCascading = false
                    coolingIDs = []
                }
            }
            .disabled(!store.anyLightOn)
            .opacity(store.anyLightOn ? 1 : 0.5)

            CircleIconButton(title: String(localized: "Einstellungen"), systemImage: "gearshape.fill", diameter: 22) { push(.settings) }
                .keyboardShortcut(",", modifiers: .command)
        }
        .animation(Theme.spring, value: store.lightsOnCount)
        .background(alignment: .top) {
            // Just a breath of the sky behind the greeting.
            SkyView(phase: phase)
                .frame(height: 62)
                .opacity(0.55)
                .padding(.horizontal, -12)
                .padding(.top, -12)
        }
        // The page stays alive while the panel is closed, so onAppear alone would keep
        // last night's greeting: refresh whenever the panel opens, and on the hour while open.
        .onAppear { phase = .now }
        .onChange(of: presentation.isPresented) {
            if presentation.isPresented { phase = .now }
        }
        .task(id: presentation.isPresented) {
            while presentation.isPresented, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if phase != .now { withAnimation(.easeInOut(duration: 0.8)) { phase = .now } }
            }
        }
    }

}

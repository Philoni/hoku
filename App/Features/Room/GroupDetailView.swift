import HueKit
import SwiftUI

struct GroupDetailView: View {
    @Environment(HueStore.self) private var store
    @Environment(AppModel.self) private var model
    @Environment(PanelPresentation.self) private var presentation
    let group: HueGroup
    let push: (Route) -> Void
    let pop: () -> Void
    @State private var selection: Int?
    /// The scene under the pointer: the page shows what it would look like.
    @State private var preview: HueScene?

    var body: some View {
        let groupedLight = store.groupedLight(for: group)
        let isOn = groupedLight?.isOn ?? false
        let colors = store.colors(for: group)
        let lights = store.lights(in: group)
        let zones = group.isZone ? [] : store.zones(in: group)
        let scenes = store.scenes(in: group)
        let smartScenes = store.smartScenes(in: group)
        let activeScene = isOn ? store.activeScene(in: group) : nil
        let isDimmable = lights.contains(where: \.supportsDimming)
        let popularity = model.scenePopularity
        let orderedScenes = SceneCarousel.order(scenes, activeSceneID: activeScene?.id, popularity: popularity)
        let previews = preview.map { scene in
            Dictionary(uniqueKeysWithValues: lights.compactMap { light in scene.preview(for: light).map { (light.id, $0) } })
        }
        let previewColors = previews.map { values in lights.compactMap { values[$0.id] }.filter(\.isOn).map(\.color) }
        let heroColors = previewColors ?? colors
        let previewBrightness = previews.map { values in
            let on = values.values.filter(\.isOn)
            return on.isEmpty ? 0 : on.map(\.brightness).reduce(0, +) / Double(on.count)
        }

        VStack(spacing: 10) {
            PageHeader(
                title: group.name,
                subtitle: "\(group.isZone ? "Zone" : "Raum") · \(lights.count) \(lights.count == 1 ? "Lampe" : "Lampen")",
                onBack: pop
            ) {
                SleepTimerButton(group: group, isOn: isOn)
            }

            SliderCard(
                value: previewBrightness ?? groupedLight?.dimming?.brightness ?? 100,
                isOn: preview != nil || isOn,
                colors: heroColors,
                height: 58,
                isDimmable: isDimmable,
                onToggle: { store.setOn(!isOn, group: group) },
                onBrightness: { store.setBrightness($0, group: group) },
                onAdjust: { store.adjustBrightness(by: $0, group: group) }
            ) { liveValue in
                if let preview {
                    CardLabel(
                        systemImage: "eye.fill",
                        title: preview.name,
                        subtitle: "Vorschau · Klicken zum Aktivieren",
                        isOn: true,
                        glow: heroColors.first ?? .yellow
                    )
                } else {
                    CardLabel(
                        systemImage: Icons.room(group.metadata?.archetype),
                        title: activeScene?.name ?? (isOn ? "Alle Lampen" : "Aus"),
                        subtitle: isOn && isDimmable ? "\(Int((groupedLight?.dimming?.brightness ?? 0).rounded())) % Helligkeit" : "Zum Dimmen ziehen",
                        isOn: isOn,
                        glow: colors.first ?? .yellow,
                        liveValue: liveValue
                    )
                }
            }
            .selectionRing(selection == 0)

            ScrollViewReader { proxy in
            PageScroll(maxHeight: ScreenFit.listHeight - 30) {
                VStack(spacing: 7) {
                    // Lights first: that's what you came for. Scenes follow, compact.
                    if !lights.isEmpty {
                        SectionTitle(text: "Lampen")
                        ForEach(Array(lights.enumerated()), id: \.element.id) { index, light in
                            LightCard(light: light, preview: previews?[light.id]) { push(.light(light.id)) }
                                .selectionRing(selection == index + 1)
                                .id(light.id)
                                .staggered(index)
                        }
                    }

                    if !zones.isEmpty {
                        SectionTitle(text: "Zonen")
                        ForEach(Array(zones.enumerated()), id: \.element.id) { index, zone in
                            GroupCard(group: zone) { push(.group(zone.id)) }
                                .selectionRing(selection == lights.count + 1 + index)
                                .id(zone.id)
                        }
                    }

                    if let activeScene, activeScene.isPlayingDynamically {
                        SpeedCard(scene: activeScene)
                            .padding(.top, 6)
                            .transition(.blurReplace.combined(with: .scale(0.96)))
                    }

                    if !scenes.isEmpty || !smartScenes.isEmpty {
                        SectionTitle(text: "Szenen", trailing: "\(scenes.count + smartScenes.count)")
                        SceneCarousel(scenes: orderedScenes, smartScenes: smartScenes, activeSceneID: activeScene?.id, favorites: Set(popularity.filter { $0.value >= 1 }.keys)) { scene in
                            setPreview(scene)
                        }
                            .staggered(lights.count)
                    }
                }
                .animation(Theme.softSpring, value: activeScene?.id)
            }
            .onChange(of: selection) {
                guard let selection, selection > 0 else { return }
                let ids = lights.map(\.id) + zones.map(\.id)
                guard ids.indices.contains(selection - 1) else { return }
                withAnimation(Theme.spring) { proxy.scrollTo(ids[selection - 1]) }
            }
            }
        }
        .keyboardNavigation(
            count: 1 + lights.count + zones.count,
            selection: $selection,
            onToggle: { index in
                switch target(index, lights: lights, zones: zones) {
                case .group(let target): store.setOn(!(store.groupedLight(for: target)?.isOn ?? false), group: target)
                case .light(let light): store.setOn(!light.isOn, light: light)
                }
            },
            onAdjust: { index, delta in
                switch target(index, lights: lights, zones: zones) {
                case .group(let target):
                    store.adjustBrightness(by: delta, group: target)
                case .light(let light):
                    store.adjustBrightness(by: delta, light: light)
                }
            },
            onOpen: { index in
                switch target(index, lights: lights, zones: zones) {
                case .group(let target): if target.id != group.id { push(.group(target.id)) }
                case .light(let light): if light.supportsColor || light.supportsColorTemperature { push(.light(light.id)) }
                }
            },
            onDigit: { digit in
                preview = nil
                presentation.previewColors = nil
                guard orderedScenes.indices.contains(digit - 1) else { return }
                Haptics.tap()
                store.recall(orderedScenes[digit - 1])
            }
        )
        .onDisappear { presentation.previewColors = nil }
    }

    /// Hovering in shows the preview at once; leaving waits a beat, so sliding from one
    /// tile to the next doesn't flicker back to the real state in between.
    private func setPreview(_ scene: HueScene?) {
        if let scene {
            withAnimation(Theme.softSpring) { preview = scene }
            presentation.previewColors = scene.displayColors
        } else {
            let leaving = preview
            Task {
                try? await Task.sleep(for: .milliseconds(140))
                guard preview?.id == leaving?.id else { return }
                withAnimation(Theme.softSpring) { preview = nil }
                presentation.previewColors = nil
            }
        }
    }

    private enum Target {
        case group(HueGroup)
        case light(Light)
    }

    /// 0 is the room itself, then its lights, then nested zones.
    private func target(_ index: Int, lights: [Light], zones: [HueGroup]) -> Target {
        if index == 0 { return .group(group) }
        if index <= lights.count { return .light(lights[index - 1]) }
        return .group(zones[index - lights.count - 1])
    }
}

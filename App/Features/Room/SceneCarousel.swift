import HueKit
import SwiftUI

/// One row of scene tiles that scrolls sideways and snaps; the active scene comes first.
struct SceneCarousel: View {
    /// Already in display order (see `order`), so digit shortcuts match positions.
    let scenes: [HueScene]
    let smartScenes: [SmartScene]
    let activeSceneID: String?
    var favorites: Set<String> = []
    var onPreview: (HueScene?) -> Void = { _ in }
    @Environment(\.isSnapshot) private var isSnapshot

    /// Active scene first, then the ones you use most, then dynamic ones, then the rest.
    static func order(_ scenes: [HueScene], activeSceneID: String?, popularity: [String: Double] = [:]) -> [HueScene] {
        scenes.enumerated().sorted { lhs, rhs in
            let left = (lhs.element.id == activeSceneID ? 0 : 1, -(popularity[lhs.element.id] ?? 0), lhs.element.supportsDynamic ? 0 : 1, lhs.offset)
            let right = (rhs.element.id == activeSceneID ? 0 : 1, -(popularity[rhs.element.id] ?? 0), rhs.element.supportsDynamic ? 0 : 1, rhs.offset)
            return left < right
        }.map(\.element)
    }

    @State private var position = ScrollPosition(edge: .leading)
    @State private var isAtStart = true
    @State private var isAtEnd = false
    /// The row nudges itself the first few times, to show there's more to swipe to.
    @AppStorage("sceneRowNudges") private var nudges = 0

    var body: some View {
        let ordered = scenes

        let tiles = LazyHStack(spacing: 7) {
            ForEach(smartScenes) { smartScene in
                SmartSceneTile(smartScene: smartScene)
            }
            ForEach(ordered) { scene in
                SceneTile(scene: scene, isActive: scene.id == activeSceneID)
            }
        }

        if isSnapshot {
            // An overlay doesn't affect layout, so the row starts at the left edge.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: SceneTile.size.height)
                .overlay(alignment: .leading) {
                    HStack(spacing: 7) {
                        ForEach(smartScenes) { SmartSceneTile(smartScene: $0) }
                        ForEach(ordered) { SceneTile(scene: $0, isActive: $0.id == activeSceneID) }
                    }
                    .fixedSize()
                }
                .clipped()
        } else {
            // Tiles are sized so the third one is always cut off: the eye reads that
            // as "there's more", and the edge fades only where more actually waits.
            ScrollView(.horizontal) {
                tiles
                    .scrollTargetLayout()
                    .padding(.vertical, 8)
            }
            .scrollIndicators(.never)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition($position)
            .onScrollGeometryChange(for: [Bool].self) { geometry in
                [
                    geometry.contentOffset.x <= 2,
                    geometry.contentOffset.x + geometry.containerSize.width >= geometry.contentSize.width - 2,
                ]
            } action: { _, edges in
                isAtStart = edges[0]
                isAtEnd = edges[1]
            }
            .mask {
                HStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: isAtStart ? 0 : 18)
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: isAtEnd ? 0 : 30)
                }
            }
            .animation(.easeOut(duration: 0.25), value: isAtStart)
            .animation(.easeOut(duration: 0.25), value: isAtEnd)
            .padding(.vertical, -8)
            .task { await nudgeIfNeeded(count: ordered.count + smartScenes.count) }
        }
    }

    private func nudgeIfNeeded(count: Int) async {
        guard count > 2, nudges < 3 else { return }
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled, isAtStart else { return }
        nudges += 1
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { position.scrollTo(x: 46) }
        try? await Task.sleep(for: .milliseconds(480))
        withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) { position.scrollTo(edge: .leading) }
    }
}

/// Scene artwork generated from the scene's palette, standing in for Hue's scene images.
struct SceneMesh: View {
    enum Motion {
        /// Frozen, e.g. in snapshots.
        case still
        /// A slow, living drift for every tile.
        case drift
        /// Faster, for a dynamic scene that is playing right now.
        case live
    }

    let colors: [Color]
    var motion = Motion.still
    /// Offsets the drift, so neighboring tiles don't move in step.
    var seed: Double = 0
    @Environment(\.isSnapshot) private var isSnapshot
    @Environment(\.isPanelVisible) private var isPanelVisible

    var body: some View {
        if motion == .still || isSnapshot {
            mesh(time: 0)
        } else {
            TimelineView(.animation(minimumInterval: motion == .live ? 1 / 30 : 1 / 15, paused: !isPanelVisible)) { context in
                mesh(time: context.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func mesh(time t: Double) -> some View {
        let palette = Self.palette(from: colors)
        let (speed, amount): (Double, Float) = switch motion {
        case .still: (0, 0)
        case .drift: (0.22, 0.13)
        case .live: (0.9, 0.18)
        }
        func p(_ x: Float, _ y: Float, _ phase: Double) -> SIMD2<Float> {
            [
                x + Float(sin(t * speed + phase + seed)) * amount,
                y + Float(cos(t * speed * 0.8 + phase + seed)) * amount,
            ]
        }
        return MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, p(0, 0.5, 1)[1]], p(0.5, 0.5, 0), [1, p(1, 0.5, 2)[1]],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: palette
        )
    }

    /// Nine stops: the palette colors plus darker shades for depth.
    private static func palette(from colors: [Color]) -> [Color] {
        let base = colors.isEmpty ? [Color.orange] : colors
        let shaded = base.map { $0.mix(with: .black, by: 0.3) }
        return (0..<9).map { index in
            index.isMultiple(of: 3) ? shaded[index / 3 % shaded.count] : base[index % base.count]
        }
    }
}

struct SceneTile: View {
    /// Two tiles and a good part of the third fit the panel: the cut-off one invites a
    /// swipe. At 116 pt only a sliver of it survived the edge fade; 108 pt leaves
    /// 40 pt of solid tile peeking out.
    static let size = CGSize(width: 108, height: 70)

    @Environment(HueStore.self) private var store
    let scene: HueScene
    let isActive: Bool
    var isFavorite = false
    var shortcut: Int?
    var onPreview: (HueScene?) -> Void = { _ in }

    var body: some View {
        let colors = scene.displayColors
        let isLive = isActive && scene.isPlayingDynamically

        Button {
            Haptics.tap()
            onPreview(nil)
            store.recall(scene)
        } label: {
            ZStack(alignment: .bottomLeading) {
                SceneMesh(colors: colors, motion: isLive ? .live : .drift, seed: Double(abs(scene.id.hashValue % 628)) / 100)
                LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)
                Text(scene.name)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    // Two lines only where there's a word break; single words shrink instead of splitting.
                    .lineLimit(scene.name.contains(" ") ? 2 : 1)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
            }
            .overlay(alignment: .topLeading) {
                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 1)
                        .padding(7)
                        .help("Nutzt du oft")
                }
            }
            .overlay(alignment: .topTrailing) {
                if scene.supportsDynamic {
                    Image(systemName: isLive ? "waveform" : "sparkles")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Circle().fill(.black.opacity(0.25)))
                        .symbolEffect(.variableColor.iterative.reversing, isActive: isLive)
                        .padding(5)
                }
            }
            .frame(width: SceneTile.size.width, height: SceneTile.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(isActive ? 0.95 : 0.1), lineWidth: isActive ? 2 : 1)
            }
            // The active scene glows, breathing slowly.
            // Only the active tile cycles; a single phase keeps the others still.
            .phaseAnimator(isActive ? [0.4, 0.75] : [0.0]) { tile, glow in
                tile.shadow(color: (colors.first ?? .clear).opacity(isActive ? glow : 0), radius: 9)
            } animation: { _ in
                .easeInOut(duration: 2.4)
            }
        }
        .buttonStyle(PressableStyle())
        .help((scene.supportsDynamic ? String(localized: "Klicken startet die Szene · Rechtsklick: dynamisch oder statisch") : String(localized: "Szene starten")) + (shortcut.map { String(localized: " · Taste \($0)") } ?? ""))
        .contextMenu {
            Button("Starten", systemImage: "play.fill") { store.recall(scene) }
            if scene.supportsDynamic {
                Button("Dynamisch starten", systemImage: "waveform") { store.recall(scene, as: .dynamic) }
                Button("Statisch starten", systemImage: "pause.fill") { store.recall(scene, as: .static) }
            }
        }
        .onHover { onPreview($0 ? scene : nil) }
        .accessibilityLabel(isActive ? "Szene \(scene.name), aktiv" : "Szene \(scene.name)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .animation(Theme.spring, value: isActive)
    }
}

struct SmartSceneTile: View {
    @Environment(HueStore.self) private var store
    let smartScene: SmartScene

    var body: some View {
        Button {
            Haptics.tap()
            store.activate(smartScene)
        } label: {
            ZStack(alignment: .bottomLeading) {
                SceneMesh(colors: [.indigo, .orange, .yellow, .blue], motion: smartScene.isActive ? .live : .drift)
                Label(smartScene.name, systemImage: "clock.fill")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(8)
            }
            .frame(width: SceneTile.size.width, height: SceneTile.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(smartScene.isActive ? 0.95 : 0.1), lineWidth: smartScene.isActive ? 2 : 1)
            }
        }
        .buttonStyle(PressableStyle())
        .help("Smarte Szene – wechselt im Tagesverlauf")
        .accessibilityLabel(smartScene.isActive ? "Smarte Szene \(smartScene.name), aktiv" : "Smarte Szene \(smartScene.name)")
    }
}

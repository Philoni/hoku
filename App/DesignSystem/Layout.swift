import AppKit
import SwiftUI

private struct SnapshotKey: EnvironmentKey {
    static let defaultValue = false
}

private struct PanelVisibleKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// True while rendering offscreen snapshots, where scroll views and appear
    /// animations don't work. (`@Entry` needs Xcode's macro plugins.)
    var isSnapshot: Bool {
        get { self[SnapshotKey.self] }
        set { self[SnapshotKey.self] = newValue }
    }

    /// False while the panel is closed. Continuous animations pause then: a hidden
    /// window still renders every frame of a running `TimelineView`.
    var isPanelVisible: Bool {
        get { self[PanelVisibleKey.self] }
        set { self[PanelVisibleKey.self] = newValue }
    }
}

/// Vertical scroll view that is only as tall as its content (up to `maxHeight`),
/// so the popover shrinks to fit. Content stays clipped to the scroll area and
/// fades out softly at the edges instead of sliding over the header.
struct PageScroll<Content: View>: View {
    var maxHeight: CGFloat = ScreenFit.listHeight
    @ViewBuilder let content: Content

    @Environment(\.isSnapshot) private var isSnapshot
    @State private var contentHeight: CGFloat = 0
    private static var overflow: CGFloat { 10 }

    var body: some View {
        if isSnapshot {
            content
        } else {
            ScrollView {
                content
                    .padding(.vertical, 4)
                    // Room to breathe at the sides: cards grow a little and glow on hover,
                    // and a scroll view cuts off everything outside its bounds.
                    .padding(.horizontal, Self.overflow)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollIndicators(.never)
            .scrollEdgeEffectStyle(.soft, for: .vertical)
            .frame(height: min(max(contentHeight, 40), maxHeight))
            // …while the cards keep exactly their width and position.
            .padding(.horizontal, -Self.overflow)
        }
    }
}

/// The panel stays as narrow as a menu bar panel on every display, but uses the
/// height a tall screen offers.
@MainActor
enum ScreenFit {
    static var height: CGFloat {
        (NSApp.keyWindow?.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
    }

    /// Height of a page's scrolling list.
    static var listHeight: CGFloat {
        min(max(height * 0.55, 430), 820)
    }

    /// Lamps shown directly inside an expanded room card before "+N weitere".
    static var inlineLamps: Int {
        switch height {
        case ..<1000: 4
        case ..<1300: 6
        default: 8
        }
    }
}

/// Rows that appear one after another, drifting down out of a soft blur.
struct CascadeModifier: ViewModifier {
    let progress: Double

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .scaleEffect(0.96 + 0.04 * progress, anchor: .top)
            .offset(y: -8 * (1 - progress))
            .blur(radius: 5 * (1 - progress))
    }
}

extension AnyTransition {
    static func cascade(_ index: Int) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(active: CascadeModifier(progress: 0), identity: CascadeModifier(progress: 1))
                .animation(Theme.softSpring.delay(0.05 + Double(min(index, 8)) * 0.06)),
            removal: .opacity.animation(.easeOut(duration: 0.14))
        )
    }
}

/// Fades and lifts views in one after another.
struct StaggeredAppear: ViewModifier {
    let index: Int
    @Environment(\.isSnapshot) private var isSnapshot
    @State private var isVisible = false

    func body(content: Content) -> some View {
        let shown = isVisible || isSnapshot
        return content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 8)
            .onAppear {
                withAnimation(Theme.softSpring.delay(Double(min(index, 8)) * 0.03)) {
                    isVisible = true
                }
            }
    }
}

extension View {
    func staggered(_ index: Int) -> some View {
        modifier(StaggeredAppear(index: index))
    }
}

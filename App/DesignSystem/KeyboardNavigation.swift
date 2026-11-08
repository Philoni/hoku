import SwiftUI

/// Arrow-key navigation for a page: ↑↓ select, ←→ dim, Space toggles, ↩ opens,
/// digits 1–9 trigger quick actions (scenes). Esc is handled by the root.
///
/// The focus ring behaves like the Mac's own keyboard focus: it only shows while
/// you use the keyboard. It glides from card to card, fades out after a few idle
/// seconds or as soon as the mouse moves, and the next key brings it back where
/// it was instead of jumping.
struct KeyboardNavigation: ViewModifier {
    let count: Int
    @Binding var selection: Int?
    var onToggle: (Int) -> Void = { _ in }
    var onAdjust: (Int, Double) -> Void = { _, _ in }
    var onOpen: (Int) -> Void = { _ in }
    var onDigit: (Int) -> Void = { _ in }

    @FocusState private var isFocused: Bool
    @Namespace private var ring
    @Environment(\.isPanelVisible) private var isPanelVisible
    /// Where the ring was before it faded out, so the next key resumes there.
    @State private var remembered: Int?
    @State private var fadeTask: Task<Void, Never>?

    private static let idleTime: Duration = .seconds(4)

    func body(content: Content) -> some View {
        content
            .environment(\.focusRingNamespace, ring)
            .focusable()
            .focusEffectDisabled()
            .focused($isFocused)
            .onAppear { isFocused = true }
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .space, .return]) { press in
                guard count > 0 else { return .ignored }
                // A hidden ring comes back first, at the card it was on.
                if selection == nil, let remembered, remembered < count {
                    select(remembered)
                    return .handled
                }
                let fineStep = press.modifiers.contains(.option)
                switch press.key {
                case .downArrow:
                    select(min((selection ?? -1) + 1, count - 1))
                case .upArrow:
                    select(max((selection ?? 1) - 1, 0))
                case .leftArrow:
                    guard let selection else { return .ignored }
                    onAdjust(selection, fineStep ? -1 : -10)
                    scheduleFade()
                case .rightArrow:
                    guard let selection else { return .ignored }
                    onAdjust(selection, fineStep ? 1 : 10)
                    scheduleFade()
                case .space:
                    guard let selection else { return .ignored }
                    Haptics.tap()
                    onToggle(selection)
                    scheduleFade()
                case .return:
                    guard let selection else { return .ignored }
                    onOpen(selection)
                default:
                    return .ignored
                }
                return .handled
            }
            .onKeyPress(characters: .decimalDigits) { press in
                guard let digit = Int(press.characters), digit >= 1 else { return .ignored }
                onDigit(digit)
                return .handled
            }
            // The mouse takes over: the ring steps aside, the position is kept.
            .onContinuousHover { phase in
                if case .active = phase, selection != nil { fade() }
            }
            .onChange(of: isPanelVisible) {
                guard !isPanelVisible else { return }
                fadeTask?.cancel()
                selection = nil
                remembered = nil
            }
            .onDisappear { fadeTask?.cancel() }
    }

    private func select(_ index: Int) {
        withAnimation(Theme.focusSpring) { selection = index }
        remembered = index
        scheduleFade()
    }

    private func scheduleFade() {
        fadeTask?.cancel()
        fadeTask = Task {
            try? await Task.sleep(for: Self.idleTime)
            guard !Task.isCancelled else { return }
            fade()
        }
    }

    private func fade() {
        fadeTask?.cancel()
        if let selection { remembered = selection }
        withAnimation(.easeOut(duration: 0.35)) { selection = nil }
    }
}

extension View {
    func keyboardNavigation(
        count: Int,
        selection: Binding<Int?>,
        onToggle: @escaping (Int) -> Void = { _ in },
        onAdjust: @escaping (Int, Double) -> Void = { _, _ in },
        onOpen: @escaping (Int) -> Void = { _ in },
        onDigit: @escaping (Int) -> Void = { _ in }
    ) -> some View {
        modifier(KeyboardNavigation(
            count: count, selection: selection,
            onToggle: onToggle, onAdjust: onAdjust, onOpen: onOpen, onDigit: onDigit
        ))
    }

    /// The keyboard focus ring on the selected card. There is only ever one ring per
    /// page; it slides to the next card instead of blinking on and off.
    func selectionRing(_ isSelected: Bool) -> some View {
        modifier(FocusRing(isSelected: isSelected))
    }
}

/// Drawn inside the card's own outline, so scroll views never cut it off.
private struct FocusRing: ViewModifier {
    let isSelected: Bool
    @Environment(\.focusRingNamespace) private var namespace
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.overlay {
            if isSelected {
                ring
                    .transition(.opacity.combined(with: .scale(0.985)))
            }
        }
    }

    @ViewBuilder private var ring: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        let view = ZStack {
            // Soft light spilling inward from the edge.
            shape
                .strokeBorder(Theme.ring, lineWidth: 5)
                .blur(radius: 4)
                .opacity(0.35)
                .clipShape(shape)
            // The crisp edge, brighter at the top like light catching glass.
            if colorScheme == .dark {
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.9), .white.opacity(0.35)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1.25
                    )
                    .blendMode(.plusLighter)
                    .opacity(0.8)
                shape.strokeBorder(Theme.ring.opacity(0.4), lineWidth: 1.25)
            } else {
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [.black.opacity(0.55), .black.opacity(0.3)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1.25
                    )
            }
        }
        .allowsHitTesting(false)

        if let namespace {
            view.matchedGeometryEffect(id: "focus-ring", in: namespace)
        } else {
            view
        }
    }
}

private struct FocusRingNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var focusRingNamespace: Namespace.ID? {
        get { self[FocusRingNamespaceKey.self] }
        set { self[FocusRingNamespaceKey.self] = newValue }
    }
}

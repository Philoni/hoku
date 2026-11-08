import AppKit

/// Routes scroll gestures to the card under the pointer: a two-finger swipe sideways,
/// or ⌥ + vertical scroll, changes its brightness. Plain vertical scrolling keeps
/// scrolling the list.
@MainActor
final class HoverDimming {
    static let shared = HoverDimming()

    private var adjusters: [UUID: (Double) -> Void] = [:]
    private var hovered: UUID?
    private var accumulated: Double = 0

    func enter(_ id: UUID, adjust: @escaping (Double) -> Void) {
        adjusters[id] = adjust
        hovered = id
        accumulated = 0
    }

    func leave(_ id: UUID) {
        adjusters[id] = nil
        if hovered == id { hovered = nil }
    }

    /// The parts of a scroll event we need (NSEvent itself isn't Sendable).
    struct Scroll: Sendable {
        var deltaX: Double
        var deltaY: Double
        var withOption: Bool
        var isNatural: Bool
        var isPrecise: Bool

        init(_ event: NSEvent) {
            deltaX = event.scrollingDeltaX
            deltaY = event.scrollingDeltaY
            withOption = event.modifierFlags.contains(.option)
            isNatural = event.isDirectionInvertedFromDevice
            isPrecise = event.hasPreciseScrollingDeltas
        }
    }

    /// Returns true if the event was used for dimming and must not scroll anything.
    func handle(_ scroll: Scroll) -> Bool {
        guard let hovered, let adjust = adjusters[hovered] else { return false }
        let isHorizontal = abs(scroll.deltaX) > abs(scroll.deltaY) * 1.2
        let isOptionScroll = scroll.withOption && !isHorizontal
        guard isHorizontal || isOptionScroll else { return false }

        // Follow the fingers: right or up means brighter, whatever the scroll direction setting.
        let raw = isHorizontal ? scroll.deltaX : -scroll.deltaY
        let fingers = scroll.isNatural ? raw : -raw
        let scale = scroll.isPrecise ? 0.35 : 4.0
        accumulated += fingers * scale

        let whole = accumulated.rounded(.towardZero)
        if whole != 0 {
            accumulated -= whole
            adjust(whole)
        }
        return true
    }
}

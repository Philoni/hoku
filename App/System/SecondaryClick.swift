import AppKit
import SwiftUI

extension View {
    /// Right-click, two-finger click or Control-click, without a context menu.
    /// Every other event passes through to the SwiftUI view underneath.
    func onSecondaryClick(perform action: @escaping () -> Void) -> some View {
        modifier(SecondaryClickModifier(action: action))
    }
}

private struct SecondaryClickModifier: ViewModifier {
    let action: () -> Void
    @Environment(\.isSnapshot) private var isSnapshot

    func body(content: Content) -> some View {
        // AppKit views don't render offscreen.
        if isSnapshot {
            content
        } else {
            content.overlay(SecondaryClickCatcher(action: action))
        }
    }
}

private struct SecondaryClickCatcher: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        CatcherView()
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.action = action
    }

    final class CatcherView: NSView {
        var action: (() -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            let isRight = event.type == .rightMouseDown || event.type == .rightMouseUp
            let isControlClick = (event.type == .leftMouseDown || event.type == .leftMouseUp)
                && event.modifierFlags.contains(.control)
            return isRight || isControlClick ? super.hitTest(point) : nil
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func rightMouseDown(with event: NSEvent) {
            action?()
        }

        /// Only reached for Control-click (see `hitTest`).
        override func mouseDown(with event: NSEvent) {
            action?()
        }

        override func menu(for event: NSEvent) -> NSMenu? { nil }
    }
}

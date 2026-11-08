import AppKit
import SwiftUI

/// Borderless, non-activating panel: it takes keyboard focus without pulling the
/// app (and its focus) away from whatever you were doing.
final class LightPanel: NSPanel {
    init(contentViewController: NSViewController) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.contentViewController = contentViewController
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Hosts the SwiftUI content *inside* AppKit's Liquid Glass (as Control Center does).
/// SwiftUI's own glass controls must live in the glass view's `contentView`; putting
/// the glass behind them as a background makes SwiftUI recurse until the stack overflows.
final class GlassContainerController: NSViewController {
    private let hosting: NSHostingController<AnyView>
    var onSizeChange: (NSSize) -> Void = { _ in }

    init(rootView: AnyView) {
        hosting = NSHostingController(rootView: rootView)
        hosting.sizingOptions = [.preferredContentSize]
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        // The window itself is rectangular. Clip everything to the rounded shape so
        // the corners stay fully transparent and the window shadow follows the curve
        // (otherwise macOS draws a rectangular frame around the panel).
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 24
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true

        let glass = NSGlassEffectView()
        glass.cornerRadius = 24
        glass.style = .regular
        glass.autoresizingMask = [.width, .height]
        addChild(hosting)
        glass.contentView = hosting.view
        container.addSubview(glass)
        view = container
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        view.subviews.first?.frame = view.bounds
        view.window?.invalidateShadow()
    }

    override func preferredContentSizeDidChange(for viewController: NSViewController) {
        super.preferredContentSizeDidChange(for: viewController)
        preferredContentSize = viewController.preferredContentSize
        onSizeChange(viewController.preferredContentSize)
    }
}

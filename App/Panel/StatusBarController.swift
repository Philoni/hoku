import AppKit
import HueKit
import Observation
import SwiftUI

/// Owns the menu bar item and the glass panel that drops down from it.
///
/// A custom `NSStatusItem` + `NSPanel` instead of SwiftUI's `MenuBarExtra`, because
/// only that allows a colored icon, a global hotkey that opens the panel, and
/// keyboard focus without activating the app (like Spotlight).
@MainActor
final class StatusBarController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel: LightPanel
    private let presentation = PanelPresentation()
    private var outsideClickMonitor: Any?
    private var scrollMonitor: Any?
    private(set) var hotKey: HotKey!
    private var coachMark: NSPanel?
    /// Called every time the panel opens (the setup assistant listens for it).
    var onPanelShown: () -> Void = {}
    var onOpenSetup: () -> Void = {} {
        didSet { presentation.openSetup = onOpenSetup }
    }

    init(model: AppModel) {
        self.model = model

        let root = PanelRoot()
            .environment(model)
            .environment(model.store)
            .environment(presentation)
        let container = GlassContainerController(rootView: AnyView(root))
        panel = LightPanel(contentViewController: container)

        super.init()
        panel.delegate = self
        container.onSizeChange = { [weak self] size in self?.resize(to: size) }
        presentation.close = { [weak self] in self?.hide() }

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Hoku")
        }
        updateIcon()
        applyAppearance()

        // Two-finger swipe sideways (or ⌥ + scroll) over a card dims it.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            let scroll = HoverDimming.Scroll(event)
            let handled = MainActor.assumeIsolated { HoverDimming.shared.handle(scroll) }
            return handled ? nil : event
        }

        hotKey = HotKey()
        registerShortcuts()
        model.onHotKeyChange = { [weak self] _ in self?.registerShortcuts() }
        model.onShortcutsChange = { [weak self] in self?.registerShortcuts() }
    }

    // MARK: Icon

    private var iconColors: [NSColor]?
    private var iconTask: Task<Void, Never>?

    /// Re-renders the icon whenever the lights' colors change — at most a few times a
    /// second, since dynamic scenes change colors continuously.
    private func updateIcon() {
        let colors = withObservationTracking {
            model.store.colorsOfLightsOn.compactMap { NSColor($0).usingColorSpace(.sRGB) }
        } onChange: { [weak self] in
            Task { @MainActor in self?.scheduleIconUpdate() }
        }
        guard colors != iconColors else { return }
        iconColors = colors
        statusItem.button?.image = MenuBarIcon.image(colors: colors)
    }

    private func scheduleIconUpdate() {
        guard iconTask == nil else { return }
        iconTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            self?.iconTask = nil
            self?.updateIcon()
        }
    }

    /// Follows the appearance setting (automatic = system, or forced dark/light).
    private func applyAppearance() {
        let appearance = withObservationTracking {
            model.appearance.nsAppearance
        } onChange: { [weak self] in
            Task { @MainActor in self?.applyAppearance() }
        }
        panel.appearance = appearance
        panel.invalidateShadow()
    }

    // MARK: Showing and hiding

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            toggle()
        }
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        model.store.refreshIfStale()
        model.leftOn.learnHomeIfNeeded()
        presentation.willShow()
        presentation.isPresented = true
        hideCoachMark()
        onPanelShown()

        panel.layoutIfNeeded()
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        positionPanel(below: anchor)

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel.animator().alphaValue = 1
        }
        // The shadow is computed from the window's pixels; recompute once the glass is drawn.
        DispatchQueue.main.async { [panel] in panel.invalidateShadow() }
        button.highlight(true)

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        model.activeRecorder = nil
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        statusItem.button?.highlight(false)
        presentation.isPresented = false
        presentation.didHide()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.presentation.isPresented else { return }
                self.panel.orderOut(nil)
                if !self.presentation.holdsPage { self.presentation.resetNavigation() }
            }
        }
    }

    private var anchorTop: CGFloat = 0

    // MARK: Shortcuts

    private var registeredShortcuts: [UInt32] = []

    private func registerShortcuts() {
        registeredShortcuts.forEach { hotKey.unregister($0) }
        registeredShortcuts = []
        guard model.activeRecorder == nil else { return }
        let panelID = hotKey.register(model.hotKeyCombination, action: { [weak self] in self?.toggle() })
        if let panelID { registeredShortcuts.append(panelID) }
        model.isPanelHotKeyUnavailable = panelID == nil
        var unavailable: Set<LightShortcut.Target> = []
        for shortcut in model.shortcuts {
            let target = shortcut.target
            if let id = hotKey.register(shortcut.combination, action: { [weak self] in self?.run(target) }) {
                registeredShortcuts.append(id)
            } else {
                unavailable.insert(target)
            }
        }
        model.unavailableShortcuts = unavailable
    }

    private func run(_ target: LightShortcut.Target) {
        let feedback = model.perform(target)
        // With the panel open the cards themselves show what happened.
        if !panel.isVisible || feedback.isProblem { show(feedback) }
    }

    private var feedbackPanel: NSPanel?
    private var feedbackTask: Task<Void, Never>?

    private func show(_ feedback: ShortcutFeedback) {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let host = NSHostingView(rootView: ShortcutFeedbackView(feedback: feedback))
        let size = host.fittingSize
        let frame = NSRect(x: anchor.midX - size.width / 2, y: anchor.minY - size.height - 4, width: size.width, height: size.height)

        let hud = feedbackPanel ?? {
            let hud = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            hud.isOpaque = false
            hud.backgroundColor = .clear
            hud.hasShadow = false
            hud.level = .statusBar
            hud.ignoresMouseEvents = true
            hud.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
            hud.alphaValue = 0
            feedbackPanel = hud
            return hud
        }()
        hud.appearance = model.appearance.nsAppearance
        hud.contentView = host
        hud.setFrame(frame, display: true)
        hud.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            hud.animator().alphaValue = 1
        }

        feedbackTask?.cancel()
        feedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(feedback.isProblem ? 2.6 : 1.4))
            guard !Task.isCancelled, let self, let hud = self.feedbackPanel else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                hud.animator().alphaValue = 0
            }
            if !Task.isCancelled { hud.orderOut(nil) }
        }
    }

    // MARK: Coach mark

    /// A glowing arrow under the menu bar icon: "Hoku lives here". Used by setup.
    func showCoachMark() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        hideCoachMark()
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = NSSize(width: 190, height: 86)
        let panel = NSPanel(
            contentRect: NSRect(x: anchor.midX - size.width / 2, y: anchor.minY - size.height - 2, width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: CoachMarkView(hotKey: model.hotKeyCombination.displayString))
        panel.orderFrontRegardless()
        coachMark = panel
        Task { [weak self, weak panel] in
            try? await Task.sleep(for: .seconds(6))
            if let panel, self?.coachMark === panel { self?.hideCoachMark() }
        }
    }

    private func hideCoachMark() {
        coachMark?.orderOut(nil)
        coachMark = nil
    }

    /// Follows SwiftUI's preferred size, keeping the top edge under the menu bar.
    ///
    /// SwiftUI reports the *final* size the moment a page or card changes, while its
    /// content still springs there. Snapping the window to that size shows an empty
    /// strip of glass (opening a room) or crops the outgoing page (going back), so
    /// while the panel is up the window glides along on a curve close to
    /// `Theme.softSpring`.
    private func resize(to size: NSSize) {
        guard size.width > 0, size.height > 0 else { return }
        let top = panel.isVisible ? anchorTop : panel.frame.maxY
        var frame = panel.frame
        frame.size = size
        frame.origin.y = top - size.height
        guard panel.isVisible, presentation.isPresented, abs(frame.height - panel.frame.height) > 1 else {
            panel.setFrame(frame, display: true)
            panel.invalidateShadow()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.42
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.85, 0.25, 1)
            panel.animator().setFrame(frame, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.panel.invalidateShadow() }
        }
    }

    private func positionPanel(below anchor: NSRect) {
        let screen = statusItem.button?.window?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let size = panel.frame.size
        anchorTop = anchor.minY - 6
        var x = anchor.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: anchorTop))
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    // MARK: Context menu

    private func showContextMenu() {
        hide()
        let menu = NSMenu()
        let allOff = NSMenuItem(title: "Alle Lichter aus", action: #selector(allOff), keyEquivalent: "")
        allOff.target = self
        allOff.isEnabled = model.store.anyLightOn
        menu.addItem(allOff)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Hoku beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Detach again so the next left click opens the panel instead of the menu.
        statusItem.menu = nil
    }

    @objc private func allOff() {
        model.store.setAllOff()
    }
}

/// "Hier wohnt Hoku" with an arrow bouncing up to the icon.
private struct CoachMarkView: View {
    let hotKey: String
    @State private var bounce = false

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color(red: 1, green: 0.74, blue: 0.38))
                .shadow(color: .orange, radius: 6)
                .offset(y: bounce ? -4 : 2)
            VStack(spacing: 1) {
                Text("Hier wohnt Hoku").font(.system(size: 13, weight: .semibold, design: .rounded))
                Text("Klick drauf · oder \(hotKey)").font(.system(size: 11, design: .rounded)).opacity(0.75)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color(red: 0.08, green: 0.07, blue: 0.18).opacity(0.92)))
            .overlay(Capsule().strokeBorder(Color(red: 1, green: 0.74, blue: 0.38).opacity(0.6), lineWidth: 1))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { bounce = true }
        }
    }
}

/// The answer to a keyboard shortcut: a small glass capsule under the menu bar icon.
struct ShortcutFeedbackView: View {
    let feedback: ShortcutFeedback

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: feedback.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(feedback.isProblem ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.primary))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(feedback.title).font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(feedback.detail).font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .padding(.leading, 13)
        .padding(.trailing, 17)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .padding(6)
        .fixedSize()
    }
}

import AppKit
import SwiftUI

/// The setup assistant's own window. Unlike the menu bar panel it stays open while the
/// user visits System Settings, and Hoku shows up in the Dock and ⌘-Tab meanwhile, so
/// finding the way back is easy.
@MainActor
final class SetupWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?
    private(set) var wizard: WizardModel?

    var showMenuBarHint: () -> Void = {}
    var openPanel: () -> Void = {}

    init(model: AppModel) {
        self.model = model
    }

    func show(mode: WizardModel.Mode) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let wizard = WizardModel(app: model, mode: mode)
        wizard.onFinish = { [weak self] openPanel in self?.close(openingPanel: openPanel) }
        wizard.onShowMenuBar = { [weak self] in self?.showMenuBarHint() }

        let root = WizardView(model: wizard)
            .environment(model)
            .environment(model.store)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: WizardView.size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "Hoku einrichten"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(red: 0.03, green: 0.04, blue: 0.11, alpha: 1)
        window.contentView = NSHostingView(rootView: root)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        self.window = window
        self.wizard = wizard
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func close(openingPanel: Bool) {
        window?.close()
        if openingPanel {
            Task {
                // Let the window fade out first, then drop the panel down from the menu bar.
                try? await Task.sleep(for: .milliseconds(350))
                openPanel()
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
        window = nil
        wizard = nil
        // Back to a pure menu bar app: no Dock icon.
        NSApp.setActivationPolicy(.accessory)
    }
}

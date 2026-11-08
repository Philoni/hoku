import AppIntents
import AppKit
import HueKit
import SwiftUI
import UserNotifications

@main
struct HokuApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        // The menu bar item and its panel are AppKit (see StatusBarController);
        // SwiftUI only needs a scene to exist.
        Settings { EmptyView() }
    }
}

/// Owns the model so URL commands work even before the popover was ever opened.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    private var statusBar: StatusBarController?
    private var setup: SetupWindowController?

    override init() {
        let model = AppModel()
        self.model = model
        super.init()
        // App Intents that run in the app (e.g. the sleep timer) use the live store.
        AppDependencyManager.shared.add(dependency: model.store)
        // Set before launch finishes, so a click on "Ausschalten" that launched Hoku arrives.
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Snapshot.runIfRequested(model: model)
        let statusBar = StatusBarController(model: model)
        let setup = SetupWindowController(model: model)
        setup.showMenuBarHint = { [weak statusBar] in statusBar?.showCoachMark() }
        setup.openPanel = { [weak statusBar] in statusBar?.show() }
        statusBar.onPanelShown = { [weak setup] in setup?.wizard?.panelDidShow() }
        statusBar.onOpenSetup = { [weak setup, weak statusBar] in
            statusBar?.hide()
            setup?.show(mode: .fullSetup)
        }
        self.statusBar = statusBar
        self.setup = setup
        model.cloud.onFinished = { [weak statusBar] in statusBar?.show() }

        guard !Snapshot.isRequested else { return }
        if model.phase == .onboarding {
            setup.show(mode: .fullSetup)
        } else if !SetupState.noticesAccepted {
            setup.show(mode: .noticesOnly)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // The Hue sign-in callback belongs to ASWebAuthenticationSession; should a
        // browser hand it to the app instead, it is not a command.
        for url in urls where url.host() != "oauth" {
            guard let command = URLCommand(url: url) else {
                model.store.reportError("Unbekannter Befehl: \(url.absoluteString)")
                continue
            }
            if case .openPanel = command {
                statusBar?.show()
                continue
            }
            if case .closePanel = command {
                statusBar?.hide()
                continue
            }
            if case .openSetup = command {
                statusBar?.hide()
                setup?.show(mode: .fullSetup)
                continue
            }
            Task {
                // Launched via URL: wait for the first state load before resolving names.
                if model.store.lastSync == nil { await model.store.refresh() }
                if let message = command.run(on: model.store) {
                    model.store.reportError(message)
                }
            }
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Hoku is always "in front" as a menu bar app; show its reminders anyway.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        switch response.actionIdentifier {
        case LeftOnWatcher.turnOffAction: await turnLightsOffAtHome()
        // A click on the notification itself: show the lights, to switch single rooms –
        // only where the panel can reach them. Away from home it can't (the panel talks
        // to the bridge directly), and an offline panel would only look broken.
        case UNNotificationDefaultActionIdentifier: await showPanelIfHome()
        default: break
        }
    }

    private func showPanelIfHome() async {
        guard model.store.connection == .live else { return }
        statusBar?.show()
    }

    private func turnLightsOffAtHome() async {
        await model.leftOn.turnEverythingOff()
    }
}

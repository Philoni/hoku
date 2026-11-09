import AppKit
import HueKit
import Observation
import SwiftUI
@preconcurrency import UserNotifications

/// The "Unterwegs-Hinweis": when the Mac wakes up away from home and lights are
/// still on there, a notification offers to switch everything off.
///
/// It only *offers*: nothing is switched remotely without the user's click, and
/// leaving home itself is the phone's job (the Hue app's "When I leave" geofence).
/// Away is decided from the local network only (see `HomeLocation`), never from
/// the Mac's location; the cloud is asked only once the Mac is provably away.
@MainActor
@Observable
final class LeftOnWatcher {
    nonisolated static let category = "lights-left-on"
    nonisolated static let turnOffAction = "turn-off"

    var isEnabled: Bool = UserDefaults.standard.bool(forKey: "leftOnReminder") {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "leftOnReminder")
            if isEnabled {
                Task { await requestNotificationPermission() }
                schedule(.arrival, after: .zero)
            } else {
                policy = LeftOnPolicy()
            }
        }
    }

    private(set) var location: HomeLocation = .unknown
    private(set) var lastReport: LeftOnReport?
    /// Colors of the lamps in `lastReport`, for the notification's picture.
    @ObservationIgnored private var lastColors: [Color] = []
    private(set) var lastCheck: Date?
    private(set) var isChecking = false
    private(set) var notificationsDenied = false
    var error: String?

    /// Fingerprints (hashes) of routers seen while provably at home.
    private(set) var homeRouters: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "homeRouters") ?? []) {
        didSet { UserDefaults.standard.set(Array(homeRouters).sorted(), forKey: "homeRouters") }
    }

    @ObservationIgnored private let store: HueStore
    @ObservationIgnored private let connection: CloudConnection
    @ObservationIgnored private let cloud: HueCloud
    @ObservationIgnored private var policy = LeftOnPolicy()
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var signInNoticeShown = false
    @ObservationIgnored private var timer: Task<Void, Never>?

    init(store: HueStore, connection: CloudConnection, cloud: HueCloud = .shared) {
        self.store = store
        self.connection = connection
        self.cloud = cloud
        guard Features.awayReminder else {
            // A reminder left over from a build with the feature on must not offer a
            // button that would reach the cloud now.
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.category])
            return
        }
        registerCategory()
        schedule(.arrival, after: .seconds(5))
        startTimer()
    }

    // MARK: Triggers

    /// Woke up, unlocked, or the network changed. Waits for Wi-Fi to settle first,
    /// so a Mac at home is not mistaken for one away while it is still joining.
    func networkMayHaveChanged() {
        schedule(.arrival, after: .seconds(15))
    }

    private func schedule(_ trigger: LeftOnPolicy.Trigger, after delay: Duration) {
        // The demo home and snapshots must never touch the real network or cloud.
        guard isLearningHome, !Snapshot.isDemo, !Snapshot.isRequested else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.evaluate(trigger)
        }
    }

    private func startTimer() {
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(LeftOnPolicy.recheckInterval))
                guard let self else { return }
                if self.isEnabled, self.location == .away {
                    await self.evaluate(.timer)
                } else {
                    self.learnHomeIfNeeded()
                }
            }
        }
    }

    // MARK: Checking

    /// Until the home network is known, every chance to see it counts: opening the
    /// panel, and the half-hourly timer. Waking and network changes cover the rest;
    /// a Mac that stays put at home would otherwise never get a reason to look.
    func learnHomeIfNeeded() {
        guard homeRouters.isEmpty, isLearningHome, !Snapshot.isDemo, !Snapshot.isRequested,
              let credentials = store.credentials
        else { return }
        Task { await locate(credentials, retries: 0) }
    }

    /// "Jetzt prüfen" in the settings: looks right away, also at home, and never notifies.
    func checkNow() async {
        guard let credentials = store.credentials else { return }
        await locate(credentials, retries: 0)
        await fetchReport()
    }

    /// "Test-Mitteilung": the whole chain (cloud, permission, banner, button) without
    /// leaving home. Posts what the real reminder would say right now; the reminder's
    /// own bookkeeping is left alone.
    func sendTestNotification() async {
        guard await requestNotificationPermission() else { return }
        guard let credentials = store.credentials else {
            error = String(localized: "Keine Bridge gekoppelt.")
            return
        }
        await locate(credentials, retries: 0)
        // Only what this check fetched: never an older report dressed up as the test.
        guard let report = await fetchReport() else {
            if error == nil { error = String(localized: "Nicht mit Hue verbunden.") }
            return
        }
        do {
            if report.isEmpty {
                try await post(title: String(localized: "Zu Hause ist alles aus"), subtitle: String(localized: "Test"), body: String(localized: "Unterwegs bliebe Hoku jetzt still."), actions: false)
            } else {
                try await post(title: String(localized: "Zu Hause brennt noch Licht"), subtitle: String(localized: "Test"), body: report.message, actions: true, colors: lastColors)
            }
        } catch {
            self.error = String(localized: "Mitteilung nicht möglich: \(error.localizedDescription)")
        }
    }

    /// Whether macOS still lets Hoku notify (it can be switched off in System Settings
    /// at any time); shown on the settings page.
    func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsDenied = settings.authorizationStatus == .denied
    }

    /// Home is learned as soon as the remote access is being set up, even with the
    /// switch still off: otherwise the first trip after switching it on (often made
    /// away from home) stays silent, because "never seen home" must mean "unknown".
    private var isLearningHome: Bool {
        Features.awayReminder && (isEnabled || connection.status != .notConfigured)
    }

    private func evaluate(_ trigger: LeftOnPolicy.Trigger) async {
        guard isLearningHome, let credentials = store.credentials else { return }
        await locate(credentials, retries: isEnabled && trigger == .arrival ? 3 : 0)
        // A newer wake/unlock/network event replaced this one: let it do the work.
        guard isEnabled, !Task.isCancelled else { return }
        switch location {
        case .home:
            policy.cameHome()
        case .unknown:
            break
        case .away:
            guard connection.isConnected,
                  !connection.grantsOtherBridge(than: credentials),
                  policy.shouldCheck(trigger, at: .now),
                  let report = await fetchReport()
            else { return }
            guard policy.record(report, at: .now) else { return }
            do {
                try await notify(report)
            } catch {
                // Not shown (e.g. notifications switched off): don't count it as given.
                policy.reminderFailed()
                self.error = String(localized: "Mitteilung nicht möglich: \(error.localizedDescription)")
                await refreshNotificationStatus()
            }
        }
    }

    /// Decides home/away; "unknown" right after waking gets a few more tries while
    /// the network comes up.
    private func locate(_ credentials: BridgeCredentials, retries: Int) async {
        for attempt in 0...retries {
            let observation = await HomeLocation.observe(bridge: credentials, using: store.client)
            let (location, learned) = HomeLocation.decide(observation, knownHomeRouters: homeRouters)
            if learned != homeRouters { homeRouters = learned }
            self.location = location
            guard location == .unknown, attempt < retries, !Task.isCancelled else { return }
            try? await Task.sleep(for: .seconds(20))
        }
    }

    @discardableResult
    private func fetchReport() async -> LeftOnReport? {
        guard connection.isConnected else { return nil }
        // Never report (or offer to switch off) a bridge other than the paired one.
        guard !connection.grantsOtherBridge(than: store.credentials) else {
            error = String(localized: "Dein Hue-Konto gibt eine andere Bridge frei als die gekoppelte.")
            return nil
        }
        isChecking = true
        defer { isChecking = false }
        do {
            let home = LeftOnReport.home(try await cloud.resources())
            let report = LeftOnReport.from(home)
            lastColors = home.colorsOfLightsOn
            lastReport = report
            lastCheck = .now
            error = nil
            signInNoticeShown = false
            return report
        } catch CloudError.signInRequired {
            error = CloudError.signInRequired.localizedDescription
            await connection.reload()
            // Otherwise the reminder would stop without a word until someone opens the
            // settings page. Once per lost sign-in, and only if the reminder is on.
            if isEnabled, !signInNoticeShown {
                signInNoticeShown = true
                try? await post(title: String(localized: "Unterwegs-Hinweis pausiert"), body: String(localized: "Hue möchte, dass du dich neu anmeldest: Hoku → Einstellungen → Unterwegs-Hinweis."), actions: false)
            }
        } catch {
            self.error = error.localizedDescription
        }
        return nil
    }

    // MARK: Switching off

    /// The notification's "Ausschalten". Through the cloud, unless the Mac is home
    /// again by now and the bridge is right there.
    func turnEverythingOff() async {
        guard Features.awayReminder else { return }
        do {
            if store.connection == .live, location == .home {
                try await store.switchEverythingOff()
            } else {
                guard !connection.grantsOtherBridge(than: store.credentials) else {
                    throw CloudError.unexpected(String(localized: "Dein Hue-Konto gibt eine andere Bridge frei als die gekoppelte."))
                }
                var homeID = lastReport?.homeGroupedLightID
                if homeID == nil { homeID = LeftOnReport.from(resources: try await cloud.resources()).homeGroupedLightID }
                guard let homeID else { throw CloudError.unexpected(String(localized: "keine Lichtgruppe für das ganze Zuhause")) }
                try await cloud.setOn(false, groupedLight: homeID)
            }
            let switchedOff = lastReport?.lightIDs.count ?? 0
            lastReport = LeftOnReport(rooms: [], lightIDs: [], homeGroupedLightID: lastReport?.homeGroupedLightID)
            _ = policy.record(lastReport!, at: .now)
            try? await post(
                title: String(localized: "Alles aus"),
                body: switchedOff > 1 ? String(localized: "\(switchedOff) Lampen sind ausgeschaltet. Zu Hause ist es jetzt dunkel.") : String(localized: "Zu Hause ist es jetzt dunkel."),
                actions: false
            )
        } catch {
            self.error = error.localizedDescription
            try? await post(title: String(localized: "Ausschalten hat nicht geklappt"), body: String(localized: "\(error.localizedDescription) Die Hue-App auf dem Handy schaltet auch von unterwegs."), actions: false)
        }
    }

    // MARK: Notifications

    private func registerCategory() {
        let turnOff = UNNotificationAction(
            identifier: Self.turnOffAction,
            title: String(localized: "Alles ausschalten"),
            // A locked Mac must be unlocked first: nobody else switches the home off.
            options: [.authenticationRequired]
        )
        let category = UNNotificationCategory(identifier: Self.category, actions: [turnOff], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    @discardableResult
    private func requestNotificationPermission() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        notificationsDenied = !granted
        return granted
    }

    private func notify(_ report: LeftOnReport) async throws {
        try await post(title: String(localized: "Zu Hause brennt noch Licht"), body: report.message, actions: true, colors: lastColors)
    }

    private func post(title: String, subtitle: String = "", body: String, actions: Bool, colors: [Color] = []) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.sound = actions ? .default : nil
        if actions { content.categoryIdentifier = Self.category }
        // The lamps' own colors as the picture: recognizable at a glance, like the panel.
        if !colors.isEmpty, let url = NotificationArt.png(colors: colors),
           let attachment = try? UNNotificationAttachment(identifier: "lights", url: url) {
            content.attachments = [attachment]
        }
        // One reminder on screen at a time; a newer one replaces the older.
        let request = UNNotificationRequest(identifier: Self.category, content: content, trigger: nil)
        try await UNUserNotificationCenter.current().add(request)
    }
}

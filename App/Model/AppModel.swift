import AppIntents
import AppKit
import HueKit
import Network
import Observation
import ServiceManagement
import SystemConfiguration

/// App-level state: onboarding, the bridge connection's lifecycle, and system hooks.
@MainActor
@Observable
final class AppModel {
    enum Phase {
        case onboarding
        case ready
    }

    let store = HueStore()
    /// The Hue account for the remote API, and the reminder that uses it.
    let cloud = CloudConnection()
    let leftOn: LeftOnWatcher
    private(set) var phase: Phase = .onboarding

    // Onboarding
    private(set) var discovered: [DiscoveredBridge] = []
    private(set) var isSearching = false
    /// The last search was blocked by macOS's local network privacy.
    private(set) var isLocalNetworkDenied = false
    private(set) var pairingBridge: DiscoveredBridge?
    private(set) var pairingSecondsLeft = 0
    var onboardingError: String?
    var manualHost = ""
    /// An existing application key, entered instead of pressing the link button.
    var manualKey = ""

    // Preferences
    var hotKeyCombination: HotKey.Combination = Preferences.load("hotKey") ?? .default {
        didSet {
            Preferences.save(hotKeyCombination, as: "hotKey")
            if shortcuts.contains(where: { $0.combination == hotKeyCombination }) {
                shortcuts.removeAll { $0.combination == hotKeyCombination }
            }
            onHotKeyChange(hotKeyCombination)
        }
    }

    var shortcuts: [LightShortcut] = Preferences.load("shortcuts") ?? [] {
        didSet {
            Preferences.save(shortcuts, as: "shortcuts")
            onShortcutsChange()
        }
    }

    /// Shortcuts macOS refused to register, usually because another app holds them.
    var unavailableShortcuts: Set<LightShortcut.Target> = []
    var isPanelHotKeyUnavailable = false

    /// The recorder waiting for a key press, if any. While one waits, no shortcut is
    /// registered: Carbon would swallow a known combination before the recorder sees it.
    var activeRecorder: UUID? {
        didSet {
            if (activeRecorder == nil) != (oldValue == nil) { onShortcutsChange() }
        }
    }

    var appearance: AppearanceMode = Preferences.load("appearance") ?? .automatic {
        didSet { Preferences.save(appearance, as: "appearance") }
    }

    var awayAutomation: AwayAutomation = Preferences.load("awayAutomation") ?? AwayAutomation() {
        didSet { Preferences.save(awayAutomation, as: "awayAutomation") }
    }

    /// The single place that changes the order of rooms and zones, so it is always saved.
    func updateGroupOrder(_ change: (inout GroupOrder) -> Void) {
        var order = store.groupOrder
        change(&order)
        store.groupOrder = order
        if !Snapshot.isDemo { Preferences.save(order, as: "groupOrder") }
    }

    /// What the user turns on when; makes suggestions personal.
    private(set) var usage = UsageFile.load()

    @ObservationIgnored var onHotKeyChange: (HotKey.Combination) -> Void = { _ in }
    @ObservationIgnored var onShortcutsChange: () -> Void = {}
    @ObservationIgnored private var isAway = false
    @ObservationIgnored private var lightsOnBeforeAway: [String] = []

    @ObservationIgnored private var pairingTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private var lastRecoveryAttempt: Date = .distantPast
    @ObservationIgnored private var networkWasSatisfied = true

    init() {
        leftOn = LeftOnWatcher(store: store, connection: cloud)
        store.nameHistory = NameHistory.load()
        // The demo home has its own rooms; a saved order belongs to the real ones.
        if !Snapshot.isDemo { store.groupOrder = Preferences.load("groupOrder") ?? GroupOrder() }
        store.onSceneActivated = { [weak self] scene in
            self?.usage.record(sceneID: scene.id)
            if let usage = self?.usage { UsageFile.save(usage) }
        }
        if Snapshot.isDemo {
            phase = .ready
        } else if let credentials = CredentialStore.load() {
            phase = .ready
            store.connect(credentials)
        }
        observeSystem()
        startRecoveryLoop()
        syncSystemIntegrations()
    }

    // MARK: Siri and Shortcuts

    @ObservationIgnored private var savedSnapshot = EntitySnapshot.load()
    @ObservationIgnored private var didAnnounceParameters = false
    @ObservationIgnored private var syncTask: Task<Void, Never>?

    /// Keeps the entity list current for Siri and Shortcuts parameters, and remembers
    /// renames — also those made in the Hue app while Hoku wasn't running, since the
    /// saved snapshot is from the last run.
    private func syncSystemIntegrations() {
        // The demo home must never replace the real entity list or name history.
        guard !Snapshot.isDemo else { return }
        let snapshot = withObservationTracking {
            store.entitySnapshot
        } onChange: { [weak self] in
            Task { @MainActor in self?.scheduleSync() }
        }

        // Siri only expands phrases like "Hoku ${room} an" after the app has told it
        // the current rooms, lights and scenes — so do that on every launch, not only on changes.
        if !snapshot.rooms.isEmpty, snapshot != savedSnapshot || !didAnnounceParameters {
            if let savedSnapshot, store.nameHistory.recordRenames(from: savedSnapshot, to: snapshot) {
                try? store.nameHistory.save()
            }
            savedSnapshot = snapshot
            try? snapshot.save()
            didAnnounceParameters = true
            HokuShortcuts.updateAppShortcutParameters()
        }
    }

    /// Lamps change many times a second during dynamic scenes; names rarely do.
    /// Coalesce, then compare once.
    private func scheduleSync() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.syncSystemIntegrations()
        }
    }

    // MARK: Onboarding

    /// `preferring`: addresses a Bonjour browser already found (the setup's network step);
    /// they are verified first, so the bridge appears without a second search.
    func search(preferring hosts: [String] = []) async {
        isSearching = true
        onboardingError = nil
        var bridges = await BridgeDiscovery.verify(hosts, using: store.client)
        var denied = false
        if bridges.isEmpty {
            let result = await BridgeDiscovery.search(using: store.client)
            bridges = result.bridges
            denied = result.isLocalNetworkDenied
        }
        discovered = bridges
        isLocalNetworkDenied = denied
        isSearching = false
    }

    func addManualBridge() async {
        let host = manualHost.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return }
        onboardingError = nil
        do {
            let bridge = try await BridgeDiscovery.bridge(at: host, using: store.client)
            let keyText = manualKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !keyText.isEmpty else {
                if !discovered.contains(bridge) { discovered.append(bridge) }
                return
            }
            guard let key = ApplicationKey.normalized(keyText) else {
                onboardingError = String(localized: "Das sieht nicht nach einem Hue-Schlüssel aus.")
                return
            }
            let credentials = try await store.client.connect(to: bridge, applicationKey: key)
            try CredentialStore.save(credentials)
            manualKey = ""
            phase = .ready
            store.connect(credentials)
        } catch {
            onboardingError = error.localizedDescription
        }
    }

    /// Points Hoku at a new address for the bridge it already knows, e.g. after the
    /// router gave it another one. Returns an error message, or nil on success.
    func changeBridgeHost(to text: String) async -> String? {
        let host = text.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, let credentials = store.credentials else { return nil }
        do {
            let bridge = try await BridgeDiscovery.bridge(at: host, using: store.client)
            guard bridge.id == credentials.bridgeID.lowercased() else {
                return String(localized: "Unter dieser Adresse antwortet eine andere Bridge.")
            }
            // The bridge may have been disconnected while the address was being checked.
            guard store.credentials?.bridgeID == credentials.bridgeID else { return nil }
            var updated = credentials
            updated.host = host
            try CredentialStore.save(updated)
            store.connect(updated)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func pair(with bridge: DiscoveredBridge) {
        pairingTask?.cancel()
        pairingBridge = bridge
        onboardingError = nil
        pairingTask = Task {
            do {
                let credentials = try await store.client.pair(
                    with: bridge,
                    // Not `Host.current()`: it resolves names over the network and can block.
                    deviceName: (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "Mac"
                ) { [weak self] seconds in
                    self?.pairingSecondsLeft = seconds
                }
                try CredentialStore.save(credentials)
                pairingBridge = nil
                phase = .ready
                store.connect(credentials)
            } catch is CancellationError {
                pairingBridge = nil
            } catch {
                pairingBridge = nil
                onboardingError = error.localizedDescription
            }
        }
    }

    func cancelPairing() {
        pairingTask?.cancel()
        pairingTask = nil
        pairingBridge = nil
    }

    /// Removes the stored key. The bridge keeps its whitelist entry; it can be
    /// removed in the Hue app under Settings → Apps.
    func forgetBridge() {
        manualKey = ""
        store.forget()
        CredentialStore.delete()
        discovered = []
        phase = .onboarding
    }

    // MARK: Launch at login

    var launchesAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                store.reportError(String(localized: "Autostart: \(error.localizedDescription)"))
            }
        }
    }

    // MARK: System events

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.store.reconnect()
                self?.store.finishExpiredFadeOuts()
                self?.leftOn.networkMayHaveChanged()
            }
        })

        // Mac automations: leaving (lock, display sleep, lid closed) and coming back.
        let away: [(NotificationCenter, Notification.Name)] = [
            (workspace, NSWorkspace.willSleepNotification),
            (workspace, NSWorkspace.screensDidSleepNotification),
            (DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked")),
        ]
        let back: [(NotificationCenter, Notification.Name)] = [
            (DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked")),
        ]
        for (center, name) in away {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.userLeft() }
            })
        }
        for (center, name) in back {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.userReturned()
                    self?.leftOn.networkMayHaveChanged()
                }
            })
        }

        pathMonitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in self?.networkChanged(satisfied: satisfied) }
        }
        pathMonitor.start(queue: .global(qos: .utility))
    }

    /// Reconnect when the network comes back (Wi-Fi switch, VPN, etc.).
    private func networkChanged(satisfied: Bool) {
        if satisfied && !networkWasSatisfied { store.reconnect() }
        // Also when only the route changed (another Wi-Fi, a VPN going up or down).
        if satisfied { leftOn.networkMayHaveChanged() }
        networkWasSatisfied = satisfied
    }

    // MARK: Suggestions

    struct Suggestion {
        var scene: HueScene
        var group: HueGroup
        /// From the user's own habits rather than the time-of-day defaults.
        var isLearned: Bool
    }

    /// The scene that fits right now: learned habits first, Hue's standard scenes as fallback.
    func suggestion(for phase: DayPhase, at now: Date = .now) -> Suggestion? {
        for (sceneID, score) in usage.scores(at: now) where score >= 1.5 {
            guard let scene = store.scenes[sceneID],
                  let groupID = scene.group?.rid,
                  let group = store.group(groupID)
            else { continue }
            let isOn = store.groupedLight(for: group)?.isOn == true
            if scene.isActive && isOn { return nil } // Already the habit — nothing to suggest.
            return Suggestion(scene: scene, group: group, isLearned: true)
        }
        return store.suggestion(for: phase).map { Suggestion(scene: $0.scene, group: $0.group, isLearned: false) }
    }

    /// Overall usage per scene, for putting favorites first.
    var scenePopularity: [String: Double] { usage.popularity() }

    // MARK: Away automation

    private var awayGroups: [HueGroup] {
        let ids = awayAutomation.groupIDs
        let all = store.sortedRooms + store.sortedZones
        return ids.isEmpty ? store.sortedRooms : all.filter { ids.contains($0.id) }
    }

    private func userLeft() {
        guard awayAutomation.isEnabled, !isAway, phase == .ready else { return }
        isAway = true
        lightsOnBeforeAway = store.lightIDsOn(in: awayGroups)
        guard !lightsOnBeforeAway.isEmpty else { return }
        for group in awayGroups where store.groupedLight(for: group)?.isOn == true {
            store.setOn(false, group: group)
        }
    }

    private func userReturned() {
        guard isAway else { return }
        isAway = false
        let lightIDs = lightsOnBeforeAway
        lightsOnBeforeAway = []
        guard awayAutomation.restoresOnReturn, !lightIDs.isEmpty else { return }
        Task {
            // After waking, Wi-Fi and the event stream need a moment.
            for _ in 0..<30 where store.connection != .live {
                try? await Task.sleep(for: .milliseconds(500))
            }
            store.turnOn(lightIDs: lightIDs)
        }
    }

    /// If the bridge got a new IP via DHCP, find it again by its ID over mDNS.
    private func startRecoveryLoop() {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                await self?.recoverHostIfNeeded()
            }
        }
    }

    private func recoverHostIfNeeded() async {
        guard case .offline = store.connection,
              let credentials = store.credentials,
              Date.now.timeIntervalSince(lastRecoveryAttempt) > 60
        else { return }
        lastRecoveryAttempt = .now

        // mDNS only: this runs every minute while offline, too often for the cloud lookup.
        let bridges = await BridgeDiscovery.discover(using: store.client, timeout: .seconds(3), usesCloud: false)
        guard let match = bridges.first(where: { $0.id == credentials.bridgeID.lowercased() }),
              match.host != credentials.host
        else { return }

        var updated = credentials
        updated.host = match.host
        try? CredentialStore.save(updated)
        store.connect(updated)
    }
}

import AppKit
import HueKit
import Observation
import ServiceManagement
import SwiftUI

/// The setup assistant's state: which step, what's done, and each step's logic.
@MainActor
@Observable
final class WizardModel {
    enum Step: Int, CaseIterable, Comparable {
        case location, welcome, home, network, bridge, menuBar, login, voice, done

        static func < (lhs: Step, rhs: Step) -> Bool { lhs.rawValue < rhs.rawValue }

        /// Each step tints the sky and the star a little differently.
        var accent: Color {
            switch self {
            case .location: Color(red: 0.72, green: 0.80, blue: 1.00)
            case .welcome: Color(red: 1.00, green: 0.74, blue: 0.38)
            case .home: Color(red: 1.00, green: 0.62, blue: 0.62)
            case .network: Color(red: 0.52, green: 0.74, blue: 1.00)
            case .bridge: Color(red: 1.00, green: 0.64, blue: 0.32)
            case .menuBar: Color(red: 0.84, green: 0.74, blue: 1.00)
            case .login: Color(red: 0.56, green: 0.90, blue: 0.76)
            case .voice: Color(red: 0.92, green: 0.62, blue: 1.00)
            case .done: Color(red: 1.00, green: 0.82, blue: 0.46)
            }
        }
    }

    enum Mode {
        /// First run: everything.
        case fullSetup
        /// Paired before the notices existed: only confirm them.
        case noticesOnly
    }

    let app: AppModel
    var store: HueStore { app.store }
    let steps: [Step]
    private(set) var step: Step
    private(set) var completed: Set<Step> = []
    private(set) var isGoingBack = false

    /// Set by the window: closes it and hands over to the menu bar.
    @ObservationIgnored var onFinish: (_ openPanel: Bool) -> Void = { _ in }
    @ObservationIgnored var onShowMenuBar: () -> Void = {}

    init(app: AppModel, mode: Mode) {
        self.app = app
        switch mode {
        case .noticesOnly:
            steps = [.welcome]
        case .fullSetup:
            let location: [Step] = InstallLocation.current.needsMove ? [.location] : []
            steps = location + [.welcome, .home, .network, .bridge, .menuBar, .login, .voice, .done]
        }
        step = steps[0]
        if SetupState.noticesAccepted { completed.insert(.welcome) }
        phone = SetupState.phone
        wishes = SetupState.wishes
        loginStatus = SMAppService.mainApp.status
    }

    // MARK: Navigation

    var index: Int { steps.firstIndex(of: step) ?? 0 }
    var progress: Double { Double(completed.count) / Double(max(steps.count, 1)) }
    var canGoBack: Bool { index > 0 && step != .done && !isBusy }

    func goBack() {
        guard canGoBack else { return }
        isGoingBack = true
        withAnimation(Theme.softSpring) { step = steps[index - 1] }
    }

    func advance() {
        completed.insert(step)
        guard index + 1 < steps.count else {
            finish(openPanel: false)
            return
        }
        isGoingBack = false
        withAnimation(Theme.softSpring) { step = steps[index + 1] }
        didEnter(step)
    }

    func finish(openPanel: Bool) {
        browserTask?.cancel()
        if steps.count > 1 { SetupState.isCompleted = true }
        onFinish(openPanel)
    }

    private func didEnter(_ step: Step) {
        switch step {
        case .bridge: startBridgeStep()
        case .login: loginStatus = SMAppService.mainApp.status
        case .voice: prepareVoiceStep()
        default: break
        }
    }

    /// Something long-running is happening; going back would only confuse.
    var isBusy: Bool {
        app.pairingBridge != nil || network == .asking || voiceInstall.isRunning
    }

    /// Snapshot aid: show a step as if the ones before were done.
    func preview(_ target: Step) {
        isPreview = true
        if target == .home {
            phone = .android
            wishes = [.siri, .menuBar, .routines]
        }
        step = target
        completed = Set(Step.allCases.filter { $0 < target && steps.contains($0) })
        if target == .voice {
            voiceQuestion = .usesAppleHome
        }
    }

    // MARK: Primary and secondary actions per step

    struct Action {
        var title: String
        var isEnabled = true
        var perform: () -> Void
    }

    var primary: Action {
        switch step {
        case .location:
            Action(title: "In „Programme“ verschieben") { [self] in moveToApplications() }
        case .welcome:
            Action(title: steps.count == 1 ? "Verstanden" : "Verstanden – los geht’s") { [self] in acceptNotices() }
        case .home:
            Action(title: "Weiter", isEnabled: phone != nil) { [self] in advance() }
        case .network:
            switch network {
            case .explaining: Action(title: "Weiter") { [self] in startNetworkCheck() }
            case .asking: Action(title: "Warte auf macOS …", isEnabled: false) {}
            case .allowed: Action(title: "Weiter") { [self] in advance() }
            case .denied: Action(title: "Systemeinstellungen öffnen") { Self.openLocalNetworkSettings() }
            }
        case .bridge:
            if isPaired {
                Action(title: "Weiter") { [self] in advance() }
            } else if let bridge = app.discovered.first, app.discovered.count == 1, app.pairingBridge == nil {
                Action(title: "Koppeln") { [self] in app.pair(with: bridge) }
            } else {
                Action(title: "Koppeln", isEnabled: false) {}
            }
        case .menuBar:
            if panelWasShown {
                Action(title: "Weiter") { [self] in advance() }
            } else {
                Action(title: "Zeig’s mir") { [self] in onShowMenuBar() }
            }
        case .login:
            Action(title: "Weiter") { [self] in advance() }
        case .voice:
            voicePrimary
        case .done:
            Action(title: "Hoku öffnen") { [self] in
                completed.insert(.done)
                finish(openPanel: true)
            }
        }
    }

    var secondary: Action? {
        switch step {
        case .location:
            Action(title: "Nicht jetzt") { [self] in advance() }
        case .network where network == .denied:
            Action(title: "Nochmal prüfen") { [self] in startNetworkCheck() }
        case .menuBar where !panelWasShown:
            Action(title: "Überspringen") { [self] in advance() }
        case .voice where voiceInstall == .idle && voiceQuestion != .commands:
            Action(title: "Später") { [self] in advance() }
        case .voice where voiceInstall == .idle && !hasICloud:
            Action(title: "Nochmal prüfen") { [self] in recheckICloud() }
        default:
            nil
        }
    }

    // MARK: Step 0 – location

    var moveError: String?

    private func moveToApplications() {
        do {
            try InstallLocation.moveToApplicationsAndRelaunch()
        } catch {
            moveError = error.localizedDescription
        }
    }

    // MARK: Step 1 – welcome & notices

    private func acceptNotices() {
        SetupState.noticesAccepted = true
        advance()
    }

    // MARK: Step 1b – your home

    /// Which phone the user has decides what Hoku must solve: without an iPhone there is
    /// no Apple Home, and Siri on the Mac knows nothing about the lights — Hoku's core case.
    var phone: SetupState.Phone? {
        didSet {
            if !isPreview { SetupState.phone = phone }
            voiceQuestion = .usesAppleHome
        }
    }

    var wishes: Set<SetupState.Wish> = [] {
        didSet { if !isPreview { SetupState.wishes = wishes } }
    }

    /// Snapshots show example answers without saving them.
    @ObservationIgnored private var isPreview = false

    func toggle(_ wish: SetupState.Wish) {
        if wishes.contains(wish) { wishes.remove(wish) } else { wishes.insert(wish) }
    }

    // MARK: Step 2 – local network

    enum NetworkState: Equatable {
        case explaining, asking, allowed, denied
    }

    private(set) var network: NetworkState = .explaining
    @ObservationIgnored private var browserTask: Task<Void, Never>?
    @ObservationIgnored private var deniedCheck: Task<Void, Never>?

    /// Bridges the browser found while checking the permission; the bridge step uses them.
    @ObservationIgnored private(set) var foundHosts: [String] = []

    /// Starting the search is what makes macOS ask — so only after the explanation.
    /// A Bonjour browser goes "ready" even while the prompt is still open, so readiness
    /// proves nothing. What counts: bridges found, or — once the user answered the prompt
    /// (Hoku regained focus) — no "policy denied" from the system.
    func startNetworkCheck() {
        withAnimation(Theme.spring) { network = .asking }
        browserTask?.cancel()
        deniedCheck?.cancel()
        deniedCheck = nil
        foundHosts = []
        let browser = BridgeBrowser()
        let seenDenied = DeniedFlag()
        browserTask = Task { [weak self] in
            for await event in browser.events() {
                guard let self else { return }
                switch event {
                case let .found(hosts):
                    foundHosts = hosts
                    networkAllowed()
                    return
                case .deniedOrPending:
                    seenDenied.set(true)
                case .allowed:
                    seenDenied.set(false)
                case .failed:
                    break
                }
            }
        }
        deniedCheck = Task { [weak self] in
            // Lost focus = the prompt is up; back in Hoku = it was answered.
            var lostFocus = !NSApp.isActive
            var ticks = 0
            while ticks < 150 {
                try? await Task.sleep(for: .milliseconds(200))
                ticks += 1
                guard let self, !Task.isCancelled, network == .asking else { return }
                if !NSApp.isActive { lostFocus = true; continue }
                // Answered the prompt, or it never appeared (granted earlier): give the
                // browser a moment, then judge by its last word.
                if lostFocus || ticks >= 20 {
                    try? await Task.sleep(for: .milliseconds(1500))
                    guard !Task.isCancelled, network == .asking else { return }
                    if seenDenied.value {
                        withAnimation(Theme.spring) { network = .denied }
                        // Keep listening: granting it in System Settings makes the browser find bridges.
                    } else {
                        networkAllowed()
                    }
                    return
                }
            }
        }
    }

    private func networkAllowed() {
        deniedCheck?.cancel()
        guard network != .allowed else { return }
        withAnimation(Theme.spring) { network = .allowed }
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            if step == .network, network == .allowed { advance() }
        }
    }

    static func openLocalNetworkSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocalNetwork",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    // MARK: Step 3 – bridge

    var isPaired: Bool { store.credentials != nil && app.phase == .ready }

    private func startBridgeStep() {
        guard !isPaired, app.discovered.isEmpty, !app.isSearching else { return }
        Task { await app.search(preferring: foundHosts) }
    }

    // MARK: Step 4 – menu bar

    private(set) var panelWasShown = false

    /// Called when the menu bar panel opened (by click or hotkey) during setup.
    func panelDidShow() {
        guard step == .menuBar, !panelWasShown else { return }
        withAnimation(Theme.spring) { panelWasShown = true }
    }

    // MARK: Step 5 – login

    private(set) var loginStatus: SMAppService.Status = .notRegistered

    var launchesAtLogin: Bool {
        get { loginStatus == .enabled || loginStatus == .requiresApproval }
        set {
            app.launchesAtLogin = newValue
            withAnimation(Theme.spring) { loginStatus = SMAppService.mainApp.status }
        }
    }

    // MARK: Step 6 – voice

    enum VoiceQuestion: Equatable {
        case usesAppleHome, hasIPhone, appleHomeChoice, commands
    }

    enum VoiceInstall: Equatable {
        case idle
        case running(done: Int, total: Int)
        case finished(Int)
        case failed(String)

        var isRunning: Bool {
            if case .running = self { return true }
            return false
        }
    }

    private(set) var voiceQuestion: VoiceQuestion = .usesAppleHome
    private(set) var voiceMode: SetupState.VoiceMode = .full
    private(set) var showsAppleHomeGuide = false
    var selectedCommands: Set<String> = []
    private(set) var existingShortcuts: Set<String> = []
    private(set) var voiceInstall: VoiceInstall = .idle

    var smartHome: SmartHomeLinks { store.smartHomeLinks }

    /// Shortcuts only signs and imports the generated commands when the Mac is signed in
    /// with an Apple Account (iCloud). Without it, the step offers the way to sign in.
    private(set) var hasICloud = true

    private func prepareVoiceStep() {
        hasICloud = SiriCommands.isSignedIntoICloud
        Task { existingShortcuts = await SiriCommands.existingShortcutNames() }
        guard voiceQuestion == .usesAppleHome, voiceInstall == .idle else { return }
        switch phone {
        case .android?, .other?:
            // No iPhone, no Apple Home: Hoku provides every command. Nothing to ask.
            if smartHome.hasAppleHome {
                voiceQuestion = .usesAppleHome
            } else {
                choose(.full)
            }
        default:
            break
        }
    }

    func answer(usesAppleHome: Bool) {
        withAnimation(Theme.softSpring) {
            if usesAppleHome {
                choose(.homeComplement)
            } else if phone == .iPhone {
                voiceQuestion = .appleHomeChoice
            } else if phone == nil {
                voiceQuestion = .hasIPhone
            } else {
                choose(.full)
            }
        }
    }

    func answer(hasIPhone: Bool) {
        withAnimation(Theme.softSpring) {
            if hasIPhone {
                voiceQuestion = .appleHomeChoice
            } else {
                choose(.full)
            }
        }
    }

    func answer(wantsAppleHome: Bool) {
        withAnimation(Theme.softSpring) {
            showsAppleHomeGuide = wantsAppleHome
            choose(wantsAppleHome ? .homeComplement : .full)
        }
    }

    private func choose(_ mode: SetupState.VoiceMode) {
        voiceMode = mode
        SetupState.voiceMode = mode
        voiceQuestion = .commands
        selectedCommands = Set(voiceCommands.filter(\.isRecommended).map(\.id))
    }

    /// With Apple Home, Siri already switches rooms: offer only what Home can't do.
    var voiceCommands: [SiriCommand] {
        let all = SiriCommand.proposals(for: store)
        switch voiceMode {
        case .full: return all
        case .homeComplement: return all.filter { $0.kind == .scene }
        }
    }

    private var pendingCommands: [SiriCommand] {
        voiceCommands.filter { selectedCommands.contains($0.id) && !existingShortcuts.contains($0.name.lowercased()) }
    }

    func recheckICloud() {
        withAnimation(Theme.spring) { hasICloud = SiriCommands.isSignedIntoICloud }
    }

    static func openAppleAccountSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings") {
            NSWorkspace.shared.open(url)
        }
    }

    private var voicePrimary: Action {
        if voiceQuestion == .commands, !hasICloud, voiceInstall == .idle {
            return Action(title: "Später") { [self] in advance() }
        }
        switch (voiceQuestion, voiceInstall) {
        case (.commands, .idle):
            let count = pendingCommands.count
            if count == 0 { return Action(title: "Weiter") { [self] in advance() } }
            return Action(title: count == 1 ? "1 Befehl einrichten" : "\(count) Befehle einrichten") { [self] in installVoiceCommands() }
        case (.commands, .running):
            return Action(title: "Wird eingerichtet …", isEnabled: false) {}
        case (.commands, .finished), (.commands, .failed):
            return Action(title: "Weiter") { [self] in advance() }
        default:
            return Action(title: "Weiter", isEnabled: false) {}
        }
    }

    private func installVoiceCommands() {
        let commands = pendingCommands
        withAnimation(Theme.spring) { voiceInstall = .running(done: 0, total: commands.count) }
        Task {
            do {
                try await SiriCommands.install(commands) { [weak self] done in
                    self?.voiceInstall = .running(done: done, total: commands.count)
                }
                withAnimation(Theme.spring) { voiceInstall = .finished(commands.count) }
            } catch {
                withAnimation(Theme.spring) { voiceInstall = .failed(error.localizedDescription) }
            }
        }
    }
}

/// What the setup remembers between launches.
enum SetupState {
    /// Bump when the notices' wording changes, so everyone confirms the new text.
    static let noticesVersion = 2

    enum VoiceMode: String, Codable {
        /// Apple Home handles rooms; Hoku adds scenes and extras.
        case homeComplement
        /// Hoku provides all voice commands.
        case full
    }

    static var noticesAccepted: Bool {
        get { (Preferences.load("setup.noticesVersion") as Int? ?? 0) >= noticesVersion }
        set { Preferences.save(newValue ? noticesVersion : 0, as: "setup.noticesVersion") }
    }

    static var isCompleted: Bool {
        get { Preferences.load("setup.completed") ?? false }
        set { Preferences.save(newValue, as: "setup.completed") }
    }

    static var voiceMode: VoiceMode? {
        get { Preferences.load("voice.mode") }
        set { Preferences.save(newValue, as: "voice.mode") }
    }

    enum Phone: String, Codable, CaseIterable {
        case iPhone, android
        /// No smartphone, or another kind.
        case other
    }

    /// What the user wants Hoku for; tailors the tips at the end of setup.
    enum Wish: String, Codable, CaseIterable {
        case siri, menuBar, scenes, routines, away
    }

    static var phone: Phone? {
        get { Preferences.load("setup.phone") }
        set { Preferences.save(newValue, as: "setup.phone") }
    }

    static var wishes: Set<Wish> {
        get { Preferences.load("setup.wishes") ?? [.siri, .menuBar] }
        set { Preferences.save(newValue, as: "setup.wishes") }
    }
}

/// Shared between the browser's event loop and the decision task.
private final class DeniedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool { lock.withLock { flag } }
    func set(_ value: Bool) { lock.withLock { flag = value } }
}

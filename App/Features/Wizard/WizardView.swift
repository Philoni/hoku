import AppKit
import HueKit
import ServiceManagement
import SwiftUI

/// The setup assistant's window content: star, step, constellation and buttons.
struct WizardView: View {
    @Bindable var model: WizardModel
    @State private var flare = 0

    static let size = CGSize(width: 600, height: 740)

    var body: some View {
        let tint = model.step.accent

        ZStack {
            WizardBackdrop(tint: tint)

            VStack(spacing: 0) {
                HokuStar(tint: tint, brightness: 0.3 + 0.7 * model.progress, size: 40, flare: flare)
                    .frame(height: 104)
                    .padding(.top, 24)

                ZStack(alignment: .top) {
                    step(model.step)
                        .id(model.step)
                        .transition(.asymmetric(
                            insertion: .modifier(
                                active: StepSlide(offset: model.isGoingBack ? -36 : 36),
                                identity: StepSlide(offset: 0)
                            ),
                            removal: .modifier(
                                active: StepSlide(offset: model.isGoingBack ? 36 : -36),
                                identity: StepSlide(offset: 0)
                            )
                        ))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                footer(tint: tint)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 24)

            if model.step == .done {
                StarBurst(tint: tint)
                    .frame(height: 260)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .foregroundStyle(.white)
        .fontDesign(.rounded)
        .environment(\.colorScheme, .dark)
        .onChange(of: model.completed.count) { flare += 1 }
    }

    @ViewBuilder
    private func step(_ step: WizardModel.Step) -> some View {
        switch step {
        case .location: LocationStep(model: model)
        case .welcome: WelcomeStep(model: model)
        case .home: HomeSetupStep(model: model)
        case .network: NetworkStep(model: model)
        case .bridge: BridgeStep(model: model)
        case .menuBar: MenuBarStep(model: model)
        case .login: LoginStep(model: model)
        case .voice: VoiceStep(model: model)
        case .done: DoneStep(model: model)
        }
    }

    private func footer(tint: Color) -> some View {
        VStack(spacing: 16) {
            if model.steps.count > 1 {
                ConstellationProgress(
                    count: model.steps.count,
                    current: model.index,
                    completed: Set(model.completed.compactMap { model.steps.firstIndex(of: $0) }),
                    tint: tint
                )
            }
            HStack(spacing: 6) {
                if model.canGoBack {
                    Button {
                        model.goBack()
                    } label: {
                        Label("Zurück", systemImage: "chevron.left")
                    }
                    .buttonStyle(WizardQuietButtonStyle())
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                    .transition(.opacity)
                }
                Spacer()
                if let secondary = model.secondary {
                    Button(secondary.title, action: secondary.perform)
                        .buttonStyle(WizardQuietButtonStyle())
                        .disabled(!secondary.isEnabled)
                }
                let primary = model.primary
                Button(primary.title, action: primary.perform)
                    .buttonStyle(WizardPrimaryButtonStyle(tint: tint))
                    .disabled(!primary.isEnabled)
                    .keyboardShortcut(.defaultAction)
                    .contentTransition(.opacity)
            }
            .animation(Theme.spring, value: model.canGoBack)
        }
    }
}

/// Steps slide in sideways out of a soft blur.
private struct StepSlide: ViewModifier {
    let offset: CGFloat

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .opacity(offset == 0 ? 1 : 0)
            .blur(radius: offset == 0 ? 0 : 8)
    }
}

/// Title and promise of a step.
private struct StepHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 15.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 470)
        .padding(.bottom, 20)
        .wizardAppear(0)
    }
}

// MARK: - 0 · Location

private struct LocationStep: View {
    let model: WizardModel

    var body: some View {
        VStack(spacing: 0) {
            StepHeader(
                title: String(localized: "Hoku in „Programme“ verschieben?"),
                subtitle: subtitle
            )
            WizardCard(tint: model.step.accent) {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Label(currentPlace, systemImage: "arrow.down.circle")
                            .foregroundStyle(.white.opacity(0.6))
                        Label("Programme", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(model.step.accent)
                    }
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                }
            }
            Text("In „Programme“ funktionieren Autostart, Siri-Befehle und Updates zuverlässig. Hoku startet danach einmal neu.")
                .font(.system(size: 13.5, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.top, 14)
            if let error = model.moveError {
                Text(error)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.orange)
                    .padding(.top, 10)
            }
        }
    }

    private var subtitle: String {
        if case .diskImage = InstallLocation.current {
            return String(localized: "Hoku läuft gerade direkt vom Image. Hoku kopiert sich und wirft das Image danach aus.")
        }
        return String(localized: "Hoku läuft gerade aus einem Ordner wie „Downloads“.")
    }

    private var currentPlace: String {
        switch InstallLocation.current {
        case let .translocated(original): original.deletingLastPathComponent().lastPathComponent
        case .diskImage: String(localized: "Image")
        case let .elsewhere(url): url.deletingLastPathComponent().lastPathComponent
        case .applications: String(localized: "Programme")
        }
    }
}

// MARK: - 1 · Welcome

private struct WelcomeStep: View {
    let model: WizardModel

    var body: some View {
        let tint = model.step.accent
        let onlyNotices = model.steps.count == 1

        VStack(spacing: 0) {
            StepHeader(
                title: onlyNotices ? String(localized: "Kurz bevor es weitergeht") : String(localized: "Willkommen bei Hoku"),
                subtitle: onlyNotices ? String(localized: "Zwei Hinweise, die zu Hoku gehören.") : String(localized: "Deine Hue-Lichter, direkt in der Menüleiste.")
            )
            if !onlyNotices {
                VStack(spacing: 12) {
                    feature("lightbulb.max.fill", String(localized: "Jeder Raum, jede Lampe"), String(localized: "Dimmen, schalten, Szenen wählen – mit einem Klick in der Menüleiste."), tint: tint)
                        .wizardAppear(1)
                    feature("waveform", String(localized: "Siri ohne Umwege"), String(localized: "„Hey Siri, Zimmer an“ – ohne App-Namen und ohne iPhone."), tint: tint)
                        .wizardAppear(2)
                    feature("lock.shield.fill", String(localized: "Alles bleibt bei dir"), Features.awayReminder ? String(localized: "Direkt mit deiner Bridge. Kein Konto, Cloud nur, wenn du sie einschaltest.") : String(localized: "Direkt mit deiner Bridge. Kein Konto, keine Cloud."), tint: tint)
                        .wizardAppear(3)
                }
                .padding(.bottom, 18)
            }
            WizardCard(tint: tint, padding: 14, appear: onlyNotices ? 1 : 4) {
                VStack(alignment: .leading, spacing: 12) {
                    notice(
                        "info.circle.fill",
                        String(localized: "Unabhängige App"),
                        String(localized: "Hoku ist ein Open-Source-Projekt von Philoni und keine App, kein Produkt und kein Dienst von Signify (Philips Hue). Signify unterstützt oder prüft Hoku nicht – verantwortlich ist allein Philoni. Philips und Philips Hue sind Marken ihrer jeweiligen Inhaber.")
                    )
                    Divider().overlay(.white.opacity(0.1))
                    notice(
                        "heart.circle.fill",
                        String(localized: "Licht und Gesundheit"),
                        String(localized: "Bestimmte Lichtfarben, schnelle Wechsel oder Blinken können Unwohlsein auslösen – bei lichtempfindlichen Menschen auch Anfälle oder Migräne. Fühlst du dich unwohl, beende Effekt, Szene oder Hoku sofort.")
                    )
                }
            }
        }
    }

    private func feature(_ symbol: String, _ title: String, _ text: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(Circle().fill(RadialGradient(colors: [tint.opacity(0.26), tint.opacity(0.08)], center: .center, startRadius: 2, endRadius: 22)))
                .overlay(Circle().strokeBorder(tint.opacity(0.25), lineWidth: 1))
                .shadow(color: tint.opacity(0.35), radius: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(text).font(.system(size: 13, design: .rounded)).foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func notice(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(model.step.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(text)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - 1b · Your home

/// "What do you have?" – and what Hoku solves for exactly that setup.
private struct HomeSetupStep: View {
    @Bindable var model: WizardModel

    var body: some View {
        let tint = model.step.accent

        VStack(spacing: 0) {
            StepHeader(title: String(localized: "Erzähl kurz von dir"), subtitle: String(localized: "Dann richtet Hoku genau das ein, was dir fehlt."))

            Text("Welches Handy hast du?")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.bottom, 8)
            HStack(spacing: 8) {
                phoneTile(.iPhone, "iPhone", "iphone", tint: tint)
                phoneTile(.android, "Android", "candybarphone", tint: tint)
                phoneTile(.other, String(localized: "Keins / anderes"), "laptopcomputer", tint: tint)
            }

            if let phone = model.phone {
                WizardCard(tint: tint, padding: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("So hilft dir Hoku", systemImage: "sparkles")
                            .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(tint)
                        Text(Self.promise(for: phone))
                            .font(.system(size: 13.5, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 12)
                .transition(.blurReplace.combined(with: .offset(y: 6)))
                .id(phone)
            }

            Text("Was ist dir wichtig?")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.top, 18)
                .padding(.bottom, 8)
            FlowLayout(spacing: 7) {
                ForEach(SetupState.Wish.allCases, id: \.self) { wish in
                    wishChip(wish, tint: tint)
                }
            }
            .frame(maxWidth: 460)
        }
        .animation(Theme.softSpring, value: model.phone)
    }

    /// The heart of Hoku, told for each setup.
    static func promise(for phone: SetupState.Phone) -> String {
        switch phone {
        case .android:
            String(localized: "Ohne iPhone lässt sich Apple Home nicht einrichten – Siri am Mac kennt deine Lampen dann nicht. Genau diese Lücke schließt Hoku: „Hey Siri, Zimmer an“ direkt am Mac. Dazu Szenen, Wecker und alles Weitere in der Menüleiste.")
        case .iPhone:
            String(localized: "Mit dem iPhone kannst du Apple Home nutzen – Hoku ergänzt, was Home nicht kann: echte Hue-Szenen und dynamische Szenen, Wecker & Schlafen, Geräte-Check, alles blitzschnell in der Menüleiste. Und sind deine Lampen nicht in Home, bringt Hoku Siri am Mac trotzdem zum Leuchten.")
        case .other:
            String(localized: "Hoku ist deine komplette Hue-Steuerung am Mac: Räume, Lampen und Szenen in der Menüleiste, per Tastatur und per Siri – ganz ohne Handy und ohne Cloud.")
        }
    }

    private func phoneTile(_ phone: SetupState.Phone, _ title: String, _ symbol: String, tint: Color) -> some View {
        let isSelected = model.phone == phone
        return Button {
            Haptics.tap()
            model.phone = phone
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isSelected ? tint : .white.opacity(0.8))
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(isSelected ? 0.12 : 0.06))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isSelected ? tint : .white.opacity(0.1), lineWidth: isSelected ? 1.5 : 1)
                    }
                    .shadow(color: isSelected ? tint.opacity(0.4) : .clear, radius: 10)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func wishChip(_ wish: SetupState.Wish, tint: Color) -> some View {
        let isSelected = model.wishes.contains(wish)
        return Button {
            Haptics.tap()
            model.toggle(wish)
        } label: {
            Label(wish.title, systemImage: wish.symbol)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .padding(.horizontal, 11)
                .frame(height: 30)
                .foregroundStyle(isSelected ? .black.opacity(0.78) : .white.opacity(0.85))
                .background(Capsule().fill(isSelected ? AnyShapeStyle(tint) : AnyShapeStyle(.white.opacity(0.08))))
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension SetupState.Wish {
    var title: String {
        switch self {
        case .siri: String(localized: "Siri am Mac")
        case .menuBar: String(localized: "Schnell aus der Menüleiste")
        case .scenes: String(localized: "Szenen & Stimmungen")
        case .routines: String(localized: "Wecker & Schlafen")
        case .away: String(localized: "Licht aus, wenn ich gehe")
        }
    }

    var symbol: String {
        switch self {
        case .siri: "waveform"
        case .menuBar: "menubar.rectangle"
        case .scenes: "sparkles"
        case .routines: "alarm"
        case .away: "lock"
        }
    }

    /// Where to find it, for the tips at the end of setup.
    var tip: String {
        switch self {
        case .siri: String(localized: "Siri: „Hey Siri, ‹Raum› an“ – weitere Befehle unter Einstellungen → Siri-Befehle.")
        case .menuBar: String(localized: "Zwei-Finger-Klick auf eine Raumkarte zeigt ihre Lampen. Wischen dimmt.")
        case .scenes: String(localized: "Klick auf einen Raum: unten wischst du durch seine Szenen.")
        case .routines: String(localized: "⏰ oben im Panel: Lichtwecker mit Sonnenaufgang und Schlafen gehen.")
        case .away: String(localized: "Einstellungen → „Licht aus, wenn ich gehe“ – beim Sperren des Macs.")
        }
    }
}

// MARK: - 2 · Local network

private struct NetworkStep: View {
    let model: WizardModel

    var body: some View {
        let tint = model.step.accent

        VStack(spacing: 0) {
            StepHeader(
                title: String(localized: "Hoku spricht direkt mit deiner Bridge"),
                subtitle: String(localized: "Ohne Cloud – nur in deinem Netzwerk zu Hause.")
            )
            switch model.network {
            case .explaining, .asking:
                PermissionDialogPreview(tint: tint, isWaiting: model.network == .asking)
                HStack(spacing: 8) {
                    if model.network == .asking {
                        ProgressView().controlSize(.small)
                    }
                    Text(model.network == .asking
                        ? "Warte auf deine Antwort im Systemdialog …"
                        : "Gleich fragt macOS nach. Klick dann auf „Erlauben“.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .contentTransition(.opacity)
                }
                .padding(.top, 18)
            case .allowed:
                SuccessBadge(text: String(localized: "Erlaubt – danke!"), tint: tint)
                    .padding(.top, 40)
            case .denied:
                WizardCard(tint: .orange) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Der Zugriff aufs lokale Netzwerk ist aus", systemImage: "wifi.exclamationmark")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text("Ohne ihn findet Hoku deine Bridge nicht. So schaltest du ihn ein:")
                            .font(.system(size: 13.5, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                        StepList(items: [
                            String(localized: "Systemeinstellungen öffnen"),
                            String(localized: "Datenschutz & Sicherheit → Lokales Netzwerk"),
                            String(localized: "Bei „Hoku“ einschalten"),
                        ], tint: tint)
                        Text("Hoku macht danach von selbst weiter.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(tint)
                    }
                }
            }
        }
        .animation(Theme.softSpring, value: model.network)
    }
}

/// A look-alike of the macOS prompt, so it's familiar when it appears.
private struct PermissionDialogPreview: View {
    var tint: Color
    var isWaiting: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 44, height: 44)
            Text("Darf „Hoku“ nach Geräten in lokalen Netzwerken suchen?")
                .font(.system(size: 14, weight: .bold))
                .multilineTextAlignment(.center)
            Text("Hoku findet deine Hue Bridge im Netzwerk und steuert deine Lichter direkt, ohne Cloud.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                Text("Nicht erlauben")
                    .frame(maxWidth: .infinity, minHeight: 26)
                    .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.12)))
                Text("Erlauben")
                    .frame(maxWidth: .infinity, minHeight: 26)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.accentColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(tint, lineWidth: 2)
                            .padding(-4)
                            .phaseAnimator([0.0, 1.0]) { ring, phase in
                                ring.opacity(1 - phase * 0.7).scaleEffect(1 + phase * 0.06)
                            } animation: { _ in .easeInOut(duration: 1.1) }
                    }
            }
            .font(.system(size: 13, weight: .medium))
        }
        .padding(18)
        .frame(width: 280)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.17, green: 0.17, blue: 0.19))
                .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .scaleEffect(isWaiting ? 0.97 : 1)
        .opacity(isWaiting ? 0.75 : 1)
        .animation(Theme.softSpring, value: isWaiting)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Vorschau des Systemdialogs: Klick auf Erlauben")
    }
}

// MARK: - 3 · Bridge

private struct BridgeStep: View {
    @Bindable var model: WizardModel
    @State private var showsManualEntry = false

    var body: some View {
        let app = model.app
        let tint = model.step.accent

        VStack(spacing: 0) {
            if model.isPaired {
                ConnectedBridge(model: model)
            } else if let bridge = app.pairingBridge {
                StepHeader(title: String(localized: "Drück jetzt die Link-Taste"), subtitle: String(localized: "Der runde Knopf oben auf deiner Bridge „\(bridge.name)“."))
                BridgeIllustration(tint: tint, progress: Double(app.pairingSecondsLeft) / 60, isPairing: true)
                Text("Hoku wartet noch \(app.pairingSecondsLeft) Sekunden")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .padding(.top, 16)
                Button("Abbrechen") { app.cancelPairing() }
                    .buttonStyle(WizardQuietButtonStyle())
            } else if app.isSearching {
                StepHeader(title: String(localized: "Suche nach deiner Hue Bridge …"), subtitle: String(localized: "Das dauert nur ein paar Sekunden."))
                BridgeIllustration(tint: tint, progress: nil, isPairing: false)
            } else if app.discovered.isEmpty {
                StepHeader(title: String(localized: "Keine Bridge gefunden"), subtitle: app.isLocalNetworkDenied
                    ? String(localized: "macOS lässt Hoku gerade nicht ins lokale Netzwerk.")
                    : String(localized: "Ist dein Mac im selben Netzwerk wie die Bridge, und leuchten ihre Lämpchen?"))
                if app.isLocalNetworkDenied {
                    Button("Netzwerk-Einstellungen öffnen") { WizardModel.openLocalNetworkSettings() }
                        .buttonStyle(WizardQuietButtonStyle())
                }
                Button {
                    Task { await app.search() }
                } label: {
                    Label("Erneut suchen", systemImage: "arrow.clockwise")
                }
                .buttonStyle(WizardQuietButtonStyle())
                manualEntry(alwaysOpen: true)
            } else {
                StepHeader(
                    title: app.discovered.count == 1 ? String(localized: "Bridge gefunden") : String(localized: "Mehrere Bridges gefunden"),
                    subtitle: app.discovered.count == 1 ? String(localized: "Koppeln, und Hoku kennt deine Lichter.") : String(localized: "Welche möchtest du koppeln?")
                )
                VStack(spacing: 8) {
                    ForEach(app.discovered) { bridge in
                        bridgeRow(bridge, showsButton: app.discovered.count > 1, tint: tint)
                    }
                }
                manualEntry(alwaysOpen: false)
            }

            if let error = app.onboardingError, !model.isPaired, app.pairingBridge == nil {
                Text(error)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
            }
        }
        .animation(Theme.softSpring, value: app.isSearching)
        .animation(Theme.softSpring, value: app.pairingBridge)
        .animation(Theme.softSpring, value: model.isPaired)
    }

    private func bridgeRow(_ bridge: DiscoveredBridge, showsButton: Bool, tint: Color) -> some View {
        WizardCard(tint: tint, padding: 12) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 34, height: 34)
                    .overlay(Circle().strokeBorder(tint, lineWidth: 2).frame(width: 13, height: 13))
                VStack(alignment: .leading, spacing: 1) {
                    Text(bridge.name).font(.system(size: 14.5, weight: .semibold, design: .rounded))
                    Text(bridge.host).font(.system(size: 12.5, design: .rounded)).foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                if showsButton {
                    Button("Koppeln") { model.app.pair(with: bridge) }
                        .buttonStyle(WizardPrimaryButtonStyle(tint: tint))
                        .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private func manualEntry(alwaysOpen: Bool) -> some View {
        @Bindable var app = model.app
        VStack(spacing: 8) {
            if !alwaysOpen && !showsManualEntry {
                Button("Bridge nicht dabei? IP-Adresse eingeben") {
                    withAnimation(Theme.softSpring) { showsManualEntry = true }
                }
                .buttonStyle(WizardQuietButtonStyle())
            } else {
                HStack(spacing: 8) {
                    TextField("IP-Adresse, z. B. 192.168.1.20", text: $app.manualHost)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, design: .rounded))
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.08)))
                        .onSubmit { Task { await app.addManualBridge() } }
                    Button("Prüfen") { Task { await app.addManualBridge() } }
                        .buttonStyle(WizardQuietButtonStyle())
                }
                Text("Die IP findest du in der Hue-App unter Einstellungen → Hue Bridges → ⓘ.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.top, 12)
        .transition(.blurReplace)
    }
}

/// A Hue Bridge seen from above, with its round link button. While pairing, a ring
/// counts down the time left; while searching, radar waves go out.
private struct BridgeIllustration: View {
    var tint: Color
    /// Remaining fraction while pairing, nil while searching.
    var progress: Double?
    var isPairing: Bool

    var body: some View {
        ZStack {
            if !isPairing {
                ForEach(0..<3) { index in
                    Circle()
                        .stroke(tint.opacity(0.5), lineWidth: 1.5)
                        .frame(width: 130, height: 130)
                        .phaseAnimator([0.0, 1.0]) { wave, phase in
                            wave.scaleEffect(0.8 + phase * 0.9).opacity(1 - phase)
                        } animation: { _ in .easeOut(duration: 2.4).delay(Double(index) * 0.8) }
                }
            }
            if let progress {
                Circle()
                    .stroke(.white.opacity(0.08), lineWidth: 4)
                    .frame(width: 168, height: 168)
                Circle()
                    .trim(from: 0, to: max(progress, 0))
                    .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 168, height: 168)
                    .shadow(color: tint, radius: 6)
                    .animation(.linear(duration: 1), value: progress)
            }
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.97), Color(white: 0.82)], startPoint: .top, endPoint: .bottom))
                .frame(width: 112, height: 112)
                .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
                .overlay {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [Color(white: 0.9), Color(white: 0.98)], startPoint: .top, endPoint: .bottom))
                            .frame(width: 42, height: 42)
                            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                        Circle()
                            .stroke(isPairing ? tint : Color(white: 0.7), lineWidth: 3)
                            .frame(width: 42, height: 42)
                            .shadow(color: isPairing ? tint : .clear, radius: 8)
                        if isPairing {
                            Circle()
                                .stroke(tint, lineWidth: 2)
                                .frame(width: 42, height: 42)
                                .phaseAnimator([0.0, 1.0]) { ring, phase in
                                    ring.scaleEffect(1 + phase * 0.7).opacity(1 - phase)
                                } animation: { _ in .easeOut(duration: 1.2) }
                        }
                    }
                }
        }
        .frame(height: 190)
        .accessibilityHidden(true)
    }
}

/// After pairing: the bridge's rooms light up one after another.
private struct ConnectedBridge: View {
    let model: WizardModel

    var body: some View {
        let store = model.store
        let rooms = store.sortedRooms
        let tint = model.step.accent

        VStack(spacing: 0) {
            StepHeader(
                title: String(localized: "Verbunden!"),
                subtitle: rooms.isEmpty
                    ? String(localized: "Hoku lädt gerade deine Räume …")
                    : "\(rooms.count) \(rooms.count == 1 ? String(localized: "Raum") : String(localized: "Räume")) · \(store.lights.count) \(store.lights.count == 1 ? String(localized: "Lampe") : String(localized: "Lampen"))"
            )
            FlowLayout(spacing: 8) {
                ForEach(Array(rooms.enumerated()), id: \.element.id) { index, room in
                    let isOn = store.groupedLight(for: room)?.isOn == true
                    let color = store.tint(for: room) ?? tint
                    Label(room.name, systemImage: Icons.room(room.metadata?.archetype))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background {
                            Capsule()
                                .fill(isOn ? AnyShapeStyle(color.opacity(0.85)) : AnyShapeStyle(.white.opacity(0.08)))
                                .shadow(color: isOn ? color.opacity(0.7) : .clear, radius: 10)
                        }
                        .foregroundStyle(isOn ? .black.opacity(0.75) : .white)
                        .transition(.cascade(index))
                }
            }
            .frame(maxWidth: 440)
        }
        .animation(Theme.softSpring, value: rooms.map(\.id))
    }
}

// MARK: - 4 · Menu bar

private struct MenuBarStep: View {
    let model: WizardModel

    var body: some View {
        let tint = model.step.accent
        let colors = model.store.colorsOfLightsOn.compactMap { NSColor($0).usingColorSpace(.sRGB) }

        VStack(spacing: 0) {
            StepHeader(
                title: String(localized: "Hier oben wohnt Hoku"),
                subtitle: String(localized: "Klick auf das Symbol in der Menüleiste – oder drück diese Tasten, egal wo du gerade bist.")
            )
            // A little menu bar, with Hoku's icon glowing in it.
            HStack(spacing: 16) {
                Spacer()
                Image(systemName: "magnifyingglass")
                Image(systemName: "wifi")
                Image(nsImage: MenuBarIcon.image(colors: colors))
                    .renderingMode(colors.isEmpty ? .template : .original)
                    .padding(6)
                    .background(Circle().fill(tint.opacity(0.25)).shadow(color: tint, radius: 10))
                    .overlay(alignment: .bottom) {
                        // Its own phase animation: a repeating withAnimation would leak into
                        // every other change on this page.
                        Image(systemName: model.panelWasShown ? "checkmark.circle.fill" : "arrowtriangle.up.fill")
                            .font(.system(size: model.panelWasShown ? 16 : 12))
                            .foregroundStyle(tint)
                            .phaseAnimator([0.0, 1.0]) { arrow, phase in
                                arrow.offset(y: model.panelWasShown ? 26 : 20 + 6 * phase)
                            } animation: { _ in .easeInOut(duration: 0.7) }
                            .contentTransition(.symbolEffect(.replace))
                    }
                Image(systemName: "battery.75percent")
                Text("Do. 21:30").font(.system(size: 13, weight: .medium))
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.08)))
            .padding(.bottom, 44)

            Keycaps(keys: model.app.hotKeyCombination.displayString.map(String.init))

            Text(model.panelWasShown
                ? "Perfekt – genau da findest du Hoku."
                : "Siehst du das Symbol nicht? Systemeinstellungen → Menüleiste → „In Menüleiste erlauben“.")
                .font(.system(size: 13.5, weight: model.panelWasShown ? .semibold : .regular, design: .rounded))
                .foregroundStyle(model.panelWasShown ? tint : .white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.top, 22)
                .contentTransition(.opacity)
        }
        .animation(Theme.spring, value: model.panelWasShown)
    }
}

// MARK: - 5 · Launch at login

private struct LoginStep: View {
    @Bindable var model: WizardModel

    var body: some View {
        let tint = model.step.accent

        VStack(spacing: 0) {
            StepHeader(
                title: String(localized: "Beim Anmelden starten?"),
                subtitle: String(localized: "Dann sind deine Lichter immer nur einen Klick entfernt – auch nach einem Neustart.")
            )
            WizardCard(tint: tint) {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Hoku beim Anmelden starten").font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text("Läuft leise in der Menüleiste.").font(.system(size: 13, design: .rounded)).foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    GlowSwitch(isOn: model.launchesAtLogin, tint: tint) {
                        model.launchesAtLogin.toggle()
                    }
                }
            }
            if model.loginStatus == .requiresApproval {
                WizardCard(tint: .orange, padding: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("macOS möchte das noch bestätigen: Allgemein → Anmeldeobjekte & Erweiterungen → „Hoku“ einschalten.")
                            .font(.system(size: 13.5, design: .rounded))
                            .foregroundStyle(.white.opacity(0.8))
                        Button("Einstellungen öffnen") { SMAppService.openSystemSettingsLoginItems() }
                            .buttonStyle(WizardQuietButtonStyle())
                    }
                }
                .padding(.top, 10)
                .transition(.blurReplace)
            }
            Text("Jederzeit änderbar in den Hoku-Einstellungen.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 14)
        }
        .animation(Theme.softSpring, value: model.loginStatus)
    }
}

// MARK: - 6 · Voice

private struct VoiceStep: View {
    @Bindable var model: WizardModel

    var body: some View {
        let tint = model.step.accent
        let links = model.smartHome

        VStack(spacing: 0) {
            StepHeader(
                title: String(localized: "Sag einfach: „Hey Siri, Zimmer an“"),
                subtitle: String(localized: "Hoku richtet Siri-Befehle ganz ohne App-Namen für dich ein.")
            )
            switch model.voiceQuestion {
            case .usesAppleHome:
                question(String(localized: "Steuerst du deine Hue-Lichter schon mit der Home-App oder Siri auf dem iPhone?"))
                WizardChoiceButton(
                    title: String(localized: "Ja, über Apple Home"), subtitle: String(localized: "Hoku ergänzt, was Home nicht kann: Szenen & mehr"),
                    systemImage: "house.fill", isSuggested: links.hasAppleHome, tint: tint
                ) { model.answer(usesAppleHome: true) }
                WizardChoiceButton(
                    title: String(localized: "Nein"), subtitle: String(localized: "Hoku übernimmt deine Siri-Befehle"),
                    systemImage: "sparkles", isSuggested: !links.hasAppleHome, tint: tint
                ) { model.answer(usesAppleHome: false) }
                .padding(.top, 8)
            case .hasIPhone:
                question(String(localized: "Hast du ein iPhone oder iPad?"))
                WizardChoiceButton(title: String(localized: "Ja"), systemImage: "iphone", tint: tint) { model.answer(hasIPhone: true) }
                WizardChoiceButton(title: String(localized: "Nein"), systemImage: "laptopcomputer", tint: tint) { model.answer(hasIPhone: false) }
                    .padding(.top, 8)
            case .appleHomeChoice:
                question(String(localized: "Wie möchtest du Siri nutzen?"))
                WizardChoiceButton(
                    title: String(localized: "Apple Home einrichten"), subtitle: String(localized: "Am iPhone – Hoku ergänzt dann Szenen & mehr"),
                    systemImage: "house.fill", tint: tint
                ) { model.answer(wantsAppleHome: true) }
                WizardChoiceButton(
                    title: String(localized: "Nur Hoku am Mac"), subtitle: String(localized: "Alle Befehle direkt über Hoku"),
                    systemImage: "desktopcomputer", tint: tint
                ) { model.answer(wantsAppleHome: false) }
                .padding(.top, 8)
            case .commands:
                commands(tint: tint)
            }
        }
        .animation(Theme.softSpring, value: model.voiceQuestion)
    }

    private func question(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .multilineTextAlignment(.center)
            .padding(.bottom, 14)
            .transition(.blurReplace)
    }

    @ViewBuilder
    private func commands(tint: Color) -> some View {
        if model.showsAppleHomeGuide {
            WizardCard(tint: tint, padding: 10) {
                Label("Am iPhone: Home-App → + → Gerät hinzufügen → Code unten auf der Bridge scannen.", systemImage: "house")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.bottom, 10)
        }
        if !model.hasICloud, model.voiceInstall == .idle {
            WizardCard(tint: .orange) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Dein Mac ist nicht mit einem Apple Account angemeldet", systemImage: "icloud.slash")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("Eigene Siri-Befehle brauchen diese Anmeldung – macOS signiert jeden Kurzbefehl darüber. Melde dich an, dann richtet Hoku die Befehle ein. Alles andere funktioniert auch ohne.")
                        .font(.system(size: 13.5, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Apple Account öffnen") { WizardModel.openAppleAccountSettings() }
                        .buttonStyle(WizardQuietButtonStyle())
                }
            }
        } else {
        switch model.voiceInstall {
        case .idle:
            let commands = model.voiceCommands
            if commands.isEmpty {
                Text("Für diese Auswahl gibt es gerade keine Befehle – du kannst sie später in den Einstellungen anlegen.")
                    .font(.system(size: 13.5, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            } else {
                ScrollView {
                    FlowChips(
                        options: commands.map { ($0.id, model.existingShortcuts.contains($0.name.lowercased()) ? "✓ \($0.name)" : $0.name) },
                        isSelected: { id in model.selectedCommands.contains(id) || model.existingShortcuts.contains(id.lowercased()) },
                        toggle: { id in
                            guard !model.existingShortcuts.contains(id.lowercased()) else { return }
                            if model.selectedCommands.contains(id) { model.selectedCommands.remove(id) } else { model.selectedCommands.insert(id) }
                        }
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
                .frame(maxHeight: 170)
                Text("Die Kurzbefehle-App fragt bei jedem Befehl einmal nach – klick jeweils auf „Kurzbefehl hinzufügen“. Beim ersten Benutzen fragt macOS je Befehl noch einmal, ob er Hoku öffnen darf: dauerhaft erlauben, dann nie wieder.")
                    .font(.system(size: 12.5, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
            }
        case let .running(done, total):
            VStack(spacing: 10) {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .tint(tint)
                    .frame(width: 260)
                Text("\(done) von \(total) an die Kurzbefehle-App übergeben …")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .monospacedDigit()
            }
            .padding(.top, 20)
        case let .finished(count):
            SuccessBadge(text: count == 1 ? String(localized: "1 Befehl eingerichtet") : String(localized: "\(count) Befehle eingerichtet"), tint: tint)
                .padding(.top, 20)
            Text("Probier’s aus: „Hey Siri, \(model.voiceCommands.first(where: \.isRecommended)?.name ?? String(localized: "Alles aus"))“")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 10)
        case let .failed(message):
            Text(message)
                .font(.system(size: 13.5, design: .rounded))
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
                .padding(.top, 20)
        }
        }
    }
}

// MARK: - 7 · Done

private struct DoneStep: View {
    let model: WizardModel

    var body: some View {
        let tint = model.step.accent
        let store = model.store
        let siriDone: Bool = if case .finished = model.voiceInstall { true } else { false }
        let siri: String = switch model.voiceInstall {
        case let .finished(count): count == 1 ? String(localized: "1 Befehl") : String(localized: "\(count) Befehle")
        case .failed: String(localized: "Nicht eingerichtet")
        default: String(localized: "Später in den Einstellungen")
        }
        let networkDone = model.isPaired || model.network == .allowed

        VStack(spacing: 0) {
            StepHeader(title: String(localized: "Alles bereit"), subtitle: String(localized: "Hoku wartet oben in der Menüleiste auf dich."))
            WizardCard(tint: tint) {
                VStack(spacing: 12) {
                    row(String(localized: "Bridge"), model.isPaired ? (store.credentials?.name ?? String(localized: "Verbunden")) : String(localized: "Nicht gekoppelt"), done: model.isPaired, index: 0, tint: tint)
                    row(String(localized: "Lokales Netzwerk"), networkDone ? String(localized: "Erlaubt") : String(localized: "Offen"), done: networkDone, index: 1, tint: tint)
                    row(String(localized: "Beim Anmelden starten"), model.launchesAtLogin ? String(localized: "An") : String(localized: "Aus"), done: model.launchesAtLogin, index: 2, tint: tint)
                    row(String(localized: "Siri"), siri, done: siriDone, index: 3, tint: tint)
                }
            }
            .frame(maxWidth: 400)

            // Tips for what the user said matters to them.
            let wishes = SetupState.Wish.allCases.filter { model.wishes.contains($0) }.prefix(3)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(wishes), id: \.self) { wish in
                    Label(wish.tip, systemImage: wish.symbol)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 400, alignment: .leading)
            .padding(.top, 16)
        }
    }

    private func row(_ title: String, _ value: String, done: Bool, index: Int, tint: Color) -> some View {
        HStack {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(done ? tint : .white.opacity(0.35))
                .font(.system(size: 16, weight: .semibold))
            Text(title).font(.system(size: 14.5, weight: .medium, design: .rounded))
            Spacer()
            Text(value).font(.system(size: 13.5, design: .rounded)).foregroundStyle(.white.opacity(0.6))
        }
        .transition(.cascade(index))
    }
}

// MARK: - Small pieces

private struct SuccessBadge: View {
    let text: String
    var tint: Color

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.black.opacity(0.75))
                .frame(width: 64, height: 64)
                .background(Circle().fill(tint).shadow(color: tint, radius: 16))
                .symbolEffect(.bounce, options: .nonRepeating)
            Text(text).font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .transition(.scale(0.8).combined(with: .opacity))
    }
}

private struct StepList: View {
    let items: [String]
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 8) {
                    Text("\(index + 1)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.75))
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(tint))
                    Text(item).font(.system(size: 13.5, weight: .medium, design: .rounded))
                }
            }
        }
    }
}

/// A one-time burst of small stars from Hoku's star when setup is done.
private struct StarBurst: View {
    var tint: Color
    @State private var isOut = false

    var body: some View {
        ZStack {
            ForEach(0..<14, id: \.self) { index in
                let angle = Double(index) / 14 * 2 * .pi
                let distance: CGFloat = 70 + CGFloat(index % 3) * 26
                FourPointStar()
                    .fill(index.isMultiple(of: 2) ? tint : .white)
                    .frame(width: 8, height: 8)
                    .offset(x: isOut ? cos(angle) * distance : 0, y: isOut ? sin(angle) * distance : 0)
                    .opacity(isOut ? 0 : 1)
                    .scaleEffect(isOut ? 0.4 : 1.2)
            }
        }
        .offset(y: 76)
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).delay(0.15)) { isOut = true }
        }
    }
}

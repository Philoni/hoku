import AppKit
import HueKit
import SwiftUI

/// Settings for the "Unterwegs-Hinweis": set up the user's own Hue app, sign in,
/// and see where Hoku thinks the Mac is.
struct LeftOnReminderView: View {
    @Environment(AppModel.self) private var model
    @Environment(HueStore.self) private var store
    @Environment(PanelPresentation.self) private var presentation
    let pop: () -> Void

    var body: some View {
        let cloud = model.cloud
        let watcher = model.leftOn

        VStack(spacing: 10) {
            PageHeader(title: String(localized: "Unterwegs-Hinweis"), subtitle: String(localized: "Licht vergessen? Hoku sagt Bescheid."), onBack: pop) {
                EmptyView()
            }

            PageScroll(maxHeight: 440) {
                VStack(spacing: 7) {
                    ReminderSwitchCard(watcher: watcher, canEnable: cloud.isConnected)

                    SectionTitle(text: String(localized: "Hue-Fernzugriff"))
                    switch cloud.status {
                    case .notConfigured:
                        AppCredentialsCard(cloud: cloud)
                    case .signedOut, .signingIn:
                        SignInCard(cloud: cloud)
                    case .connected:
                        ConnectedCard(cloud: cloud, watcher: watcher)
                    }

                    if let error = cloud.error ?? watcher.error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11.5, design: .rounded))
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }

                    SectionTitle(text: String(localized: "Beim Gehen"))
                    Text("Automatisch ausschalten, wenn du gehst, macht dein Handy am besten: In der Hue-App unter Automationen „Wenn ich gehe“ → alles aus. Hoku schaltet aus der Ferne nur, wenn du in der Mitteilung auf „Alles ausschalten“ klickst.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(CardBackground())
                }
            }
        }
        .task {
            await cloud.reload()
            await watcher.refreshNotificationStatus()
        }
        // Until connected, the user leaves the panel for the password manager and the
        // browser; it must come back here, with what was typed still in place.
        .onChange(of: cloud.isConnected, initial: true) { presentation.holdsPage = !cloud.isConnected }
        // Signing in on this page is the wish for the reminder: switch it on right away
        // (macOS then asks for permission to notify) instead of leaving a silent "Aus".
        .onChange(of: cloud.isConnected) { wasConnected, isConnected in
            if !wasConnected, isConnected { watcher.isEnabled = true }
        }
        .onDisappear { presentation.holdsPage = false }
    }
}

private struct ReminderSwitchCard: View {
    @Bindable var watcher: LeftOnWatcher
    let canEnable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingSwitch(
                title: String(localized: "Unterwegs-Hinweis"),
                subtitle: canEnable ? String(localized: "Mitteilung, wenn zu Hause noch Licht brennt") : String(localized: "Erst den Hue-Fernzugriff unten einrichten"),
                systemImage: "house.and.flag.fill",
                isOn: Binding(
                    get: { watcher.isEnabled },
                    set: { watcher.isEnabled = $0 && canEnable }
                )
            )
            .opacity(canEnable || watcher.isEnabled ? 1 : 0.5)

            Divider().opacity(0.4)
            HStack {
                Label("Ort", systemImage: locationIcon)
                Spacer()
                Text(locationText).foregroundStyle(.secondary)
            }
            if watcher.isEnabled, watcher.location != .unknown {
                Text("Hoku schaut nach, wenn der Mac außerhalb deines Heimnetzes aufwacht, entsperrt wird oder das WLAN wechselt – danach alle 30 Minuten, solange er wach ist.")
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if watcher.location == .unknown {
                Text(watcher.homeRouters.isEmpty
                     ? "Hoku lernt dein Heimnetz, sobald der Mac einmal zu Hause im WLAN ist und die Bridge sieht. Bis dahin bleibt es still."
                     : "Gerade kein Netz erkannt. Ohne Netz meldet sich Hoku nicht.")
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if watcher.notificationsDenied {
                Button("Mitteilungen sind aus – in den Systemeinstellungen erlauben") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                }
                .buttonStyle(.link)
                .font(.system(size: 11, design: .rounded))
            }
        }
        .font(.system(size: 12.5, weight: .medium, design: .rounded))
        .padding(12)
        .background(CardBackground())
    }

    private var locationText: String {
        switch watcher.location {
        case .home: String(localized: "Zu Hause")
        case .away: String(localized: "Unterwegs")
        case .unknown: String(localized: "Noch unbekannt")
        }
    }

    private var locationIcon: String {
        switch watcher.location {
        case .home: "house.fill"
        case .away: "car.fill"
        case .unknown: "questionmark.circle"
        }
    }
}

/// Step 1: the user's own remote app. Signify's terms forbid sharing one.
private struct AppCredentialsCard: View {
    let cloud: CloudConnection
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Hoku braucht dafür deine eigene, kostenlose Hue-App. Einmalig, etwa fünf Minuten. Signify verlangt dafür ein Entwicklerkonto (ab 18) und die Zustimmung zu seinen Nutzungsbedingungen; die Zugangsdaten sind nur für dich.")
                .font(.system(size: 11.5, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            step(1, "Auf developers.meethue.com ein Konto anlegen und anmelden.")
            step(2, "Unter deinem Namen → „Remote Hue API appids“ → „Add new Remote Hue API app“.")
            step(3, "Als Callback-URL eintragen:")
            HStack {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(CloudAuthorization.callbackURL, forType: .string)
                    copied = true
                } label: {
                    Label(copied ? String(localized: "Kopiert") : CloudAuthorization.callbackURL, systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                Spacer()
            }
            .padding(.leading, 22)
            step(4, "Client-ID und Client-Secret hier eintragen:")

            VStack(spacing: 6) {
                TextField("Client-ID", text: $clientID)
                SecureField("Client-Secret", text: $clientSecret)
            }
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.control))

            HStack {
                Button("Seite öffnen") {
                    NSWorkspace.shared.open(URL(string: "https://developers.meethue.com/my-apps/")!)
                }
                .buttonStyle(.glass)
                Spacer()
                Button("Speichern") {
                    Task { await cloud.saveApp(clientID: clientID, clientSecret: clientSecret) }
                }
                .buttonStyle(.glassProminent)
                .disabled(clientID.isEmpty || clientSecret.isEmpty)
            }
            .controlSize(.small)

            Label("Nur im Schlüsselbund dieses Macs, nie in iCloud oder in Dateien.", systemImage: "lock.fill")
                .font(.system(size: 10.5, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(CardBackground())
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(number)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .frame(width: 16, height: 16)
                .background(Circle().fill(Theme.control))
            Text(text)
                .font(.system(size: 11.5, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Step 2: the browser login.
private struct SignInCard: View {
    let cloud: CloudConnection

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if cloud.justSignedOut {
                SignedOutNotice()
            }
            Text("Melde dich im Browser mit dem Hue-Konto an, das du auch in der Hue-App nutzt, und erlaube Hoku den Zugriff. Dein Passwort sieht Hoku dabei nie.")
                .font(.system(size: 11.5, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Andere App-Daten …") {
                    Task { await cloud.signOut(keepingApp: false) }
                }
                .buttonStyle(.glass)
                Spacer()
                if cloud.status == .signingIn {
                    ProgressView().controlSize(.small)
                    Text("Warte auf den Browser …").foregroundStyle(.secondary)
                } else {
                    Button("Bei Hue anmelden") { cloud.signIn() }
                        .buttonStyle(.glassProminent)
                }
            }
            .controlSize(.small)
            .font(.system(size: 11.5, design: .rounded))
        }
        .padding(12)
        .background(CardBackground())
    }
}

private struct ConnectedCard: View {
    @Environment(HueStore.self) private var store
    let cloud: CloudConnection
    let watcher: LeftOnWatcher

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("Verbunden", systemImage: "checkmark.icloud.fill")
                Spacer()
                if watcher.isChecking {
                    ProgressView().controlSize(.small)
                } else if let report = watcher.lastReport {
                    Text(report.isEmpty ? "Alles aus" : "\(report.lightIDs.count) an")
                        .foregroundStyle(.secondary)
                }
            }
            if cloud.grantsOtherBridge(than: store.credentials) {
                Text("Dein Hue-Konto gibt Hoku eine andere Bridge frei als die gekoppelte. Abmelden und beim Anmelden die richtige wählen.")
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let report = watcher.lastReport, !report.isEmpty {
                Text(report.message)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Abmelden") { Task { await cloud.signOut(keepingApp: true) } }
                    .buttonStyle(.glass)
                Spacer()
                Button("Test-Mitteilung") { Task { await watcher.sendTestNotification() } }
                    .buttonStyle(.glass)
                    .disabled(watcher.isChecking)
            }
            .controlSize(.small)
        }
        .font(.system(size: 12.5, weight: .medium, design: .rounded))
        .padding(12)
        .background(CardBackground())
    }
}

/// After "Abmelden": what is gone, and how to end the access at Signify for good.
/// Signify offers no endpoint to revoke a grant, but each user owns their Hue app –
/// deleting it there invalidates every sign-in made with it.
private struct SignedOutNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Abgemeldet", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
            Text("Anmeldung und Fernzugriff sind von diesem Mac gelöscht. Ganz beenden: Auf developers.meethue.com unter „Remote Hue API appids“ deine Hoku-App löschen – dann gilt bei Signify keine Anmeldung mehr.")
                .font(.system(size: 10.5, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Seite öffnen") {
                NSWorkspace.shared.open(URL(string: "https://developers.meethue.com/my-apps/")!)
            }
            .buttonStyle(.link)
            .font(.system(size: 11, design: .rounded))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.control))
    }
}

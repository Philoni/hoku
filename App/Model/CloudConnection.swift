import AppKit
import AuthenticationServices
import HueKit
import Observation
import SystemConfiguration

/// Signing in to the Hue account for the remote API, with the user's own Hue app.
///
/// The browser login runs in `ASWebAuthenticationSession` (the system browser, as
/// RFC 8252 asks): Hoku never sees the Hue password, only the one-time code that
/// comes back to `hoku://oauth`. Client ID, secret and tokens live in the Keychain.
@MainActor
@Observable
final class CloudConnection {
    enum Status: Equatable {
        /// No client ID and secret yet.
        case notConfigured
        case signedOut
        case signingIn
        case connected(bridgeID: String?)
    }

    private(set) var status: Status = .notConfigured
    private(set) var clientID = ""
    var error: String?
    /// Shows what signing out removed until the next sign-in.
    private(set) var justSignedOut = false

    /// Asked to show the panel again after the browser closes.
    @ObservationIgnored var onFinished: () -> Void = {}

    @ObservationIgnored private let cloud: HueCloud
    @ObservationIgnored private var session: ASWebAuthenticationSession?
    @ObservationIgnored private let anchor = PresentationAnchor()

    init(cloud: HueCloud = .shared) {
        self.cloud = cloud
        // Not even a Keychain read while the feature is off.
        if Features.awayReminder { Task { await reload() } }
    }

    var isConnected: Bool {
        if case .connected = status { true } else { false }
    }

    /// True if the Hue account grants a different bridge than the paired one.
    func grantsOtherBridge(than credentials: BridgeCredentials?) -> Bool {
        guard case let .connected(bridgeID?) = status, let credentials else { return false }
        return bridgeID != credentials.bridgeID.lowercased()
    }

    func reload() async {
        do {
            let account = try await cloud.account()
            clientID = account?.app.clientID ?? ""
            status = switch account {
            case nil: .notConfigured
            case let account? where account.isSignedIn: .connected(bridgeID: account.bridgeID)
            case let account?: account.app.isComplete ? .signedOut : .notConfigured
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func saveApp(clientID: String, clientSecret: String) async {
        let app = CloudAppCredentials(clientID: clientID, clientSecret: clientSecret)
        guard app.isComplete else {
            error = "Bitte Client-ID und Client-Secret eintragen."
            return
        }
        do {
            try await cloud.saveApp(app)
            error = nil
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func signIn() {
        guard status == .signedOut, !clientID.isEmpty else { return }
        error = nil
        let deviceName = (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "Mac"
        let authorization = CloudAuthorization(clientID: clientID, deviceName: deviceName)
        status = .signingIn
        justSignedOut = false

        let session = ASWebAuthenticationSession(
            url: authorization.url,
            callback: .customScheme(CloudAuthorization.callbackScheme)
        ) { @Sendable [weak self] callback, error in
            // Called on a background queue: hand over only plain values to the main actor.
            let canceled = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
            let failure = error.map { $0.localizedDescription }
            Task { @MainActor in
                await self?.finishSignIn(callback: callback, failure: failure, canceled: canceled, authorization: authorization, deviceName: deviceName)
            }
        }
        session.presentationContextProvider = anchor
        self.session = session
        if !session.start() {
            status = .signedOut
            error = "Das Anmeldefenster ließ sich nicht öffnen."
        }
    }

    private func finishSignIn(callback: URL?, failure: String?, canceled: Bool, authorization: CloudAuthorization, deviceName: String) async {
        session = nil
        defer { onFinished() }
        if canceled || failure != nil {
            status = .signedOut
            if !canceled { error = failure }
            return
        }
        do {
            guard let callback else { throw CloudAuthorization.CallbackError.missingCode }
            let code = try authorization.code(from: callback)
            _ = try await cloud.completeSignIn(code: code, authorization: authorization, deviceType: "Hoku#\(deviceName)")
            await reload()
        } catch {
            self.error = error.localizedDescription
            await reload()
        }
    }

    /// Signs out; the Hue account keeps listing "Hoku on <Mac>" under My Apps until
    /// it is removed there (Signify offers no revoke endpoint).
    func signOut(keepingApp: Bool) async {
        do {
            try await cloud.signOut(keepingApp: keepingApp)
            error = nil
            justSignedOut = true
        } catch {
            self.error = error.localizedDescription
        }
        await reload()
    }
}

/// The login sheet needs a window to attach to; a menu bar app may have none open.
private final class PresentationAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible } ?? NSWindow()
        }
    }
}

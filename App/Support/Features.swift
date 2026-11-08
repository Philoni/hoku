import Foundation

/// Features that are built and tested but not yet part of the public release.
/// `scripts/build-app.sh` (local builds) switches them on; `make release-*` and CI
/// leave them off, so a public build never shows or runs them.
enum Features {
    /// The "Unterwegs-Hinweis": lights left on at home, through the Hue cloud.
    /// Planned for 0.10. Off means no settings row, no Keychain access, no network
    /// checks, no cloud calls.
    static let awayReminder = (Bundle.main.object(forInfoDictionaryKey: "HokuAwayReminder") as? String) == "YES"
}

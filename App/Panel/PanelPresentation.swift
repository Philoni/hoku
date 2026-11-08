import Observation
import SwiftUI

/// Lets SwiftUI know whether the panel is showing, and close it (Esc).
@MainActor
@Observable
final class PanelPresentation {
    var isPresented = false
    /// Colors of a scene the pointer rests on; the background previews them.
    var previewColors: [Color]?
    /// Bumped when the panel was closed, so the next opening starts at home.
    private(set) var resetToken = 0
    /// The room card unfolded in the overview. It survives a visit to a room page and
    /// a quick close-and-reopen; after a minute away the overview starts tidy again.
    var expandedRoomID: String?
    /// Set by a page with unfinished setup (pasting app data from a password manager,
    /// the browser login): closing the panel keeps it, so the next opening comes back
    /// to it instead of home. Ten minutes later the panel starts at home again.
    @ObservationIgnored var holdsPage = false
    @ObservationIgnored private var hiddenAt: Date?
    @ObservationIgnored var close: () -> Void = {}
    /// Opens the setup assistant window.
    @ObservationIgnored var openSetup: () -> Void = {}

    func resetNavigation() {
        resetToken += 1
    }

    func didHide() {
        hiddenAt = .now
    }

    func willShow() {
        guard let hiddenAt else { return }
        let away = Date.now.timeIntervalSince(hiddenAt)
        if away > 60 { expandedRoomID = nil }
        if holdsPage, away > 10 * 60 { resetNavigation() }
    }
}

/// The panel's root: rounded shape and the open animation.
struct PanelRoot: View {
    @Environment(PanelPresentation.self) private var presentation

    var body: some View {
        RootView()
            .environment(\.isPanelVisible, presentation.isPresented)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .scaleEffect(presentation.isPresented ? 1 : 0.96, anchor: .top)
            .opacity(presentation.isPresented ? 1 : 0)
            .animation(Theme.spring, value: presentation.isPresented)
    }
}

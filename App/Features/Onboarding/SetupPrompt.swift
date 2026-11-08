import SwiftUI

/// What the menu bar panel shows before Hoku is paired: an invitation to the setup
/// assistant, which does the actual work in its own window.
struct SetupPrompt: View {
    @Environment(PanelPresentation.self) private var presentation

    var body: some View {
        VStack(spacing: 10) {
            HokuStar(tint: Color(red: 1, green: 0.74, blue: 0.38), brightness: 0.7, size: 26)
                .frame(height: 76)
            Text("Willkommen bei Hoku")
                .font(.system(size: 17, weight: .bold, design: .rounded))
            Text("Ein paar kurze Schritte, dann steuerst du deine Lichter von hier oben.")
                .font(.system(size: 12.5, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Einrichtung starten") { presentation.openSetup() }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .padding(.top, 4)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
    }
}

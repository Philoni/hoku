import HueKit
import SwiftUI

enum Route: Hashable {
    case group(String)
    case light(String)
    case settings
    case routines
    case devices
    case siriCommands
    case shortcuts
    case connection
    case roomOrder
    case leftOnReminder
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(HueStore.self) private var store
    @Environment(PanelPresentation.self) private var presentation
    @State private var path: [Route] = []
    @State private var isGoingBack = false

    var body: some View {
        Group {
            switch model.phase {
            case .onboarding:
                SetupPrompt()
                    .transition(.blurReplace)
            case .ready:
                page(for: path.last)
                    .id(path.last)
                    .transition(.asymmetric(
                        insertion: .push(from: isGoingBack ? .leading : .trailing),
                        removal: .push(from: isGoingBack ? .leading : .trailing)
                    ))
            }
        }
        .padding(12)
        // Height follows the content (scroll areas cap themselves), so the popover stays compact.
        .frame(width: Theme.width, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            AmbientBackground(colors: presentation.previewColors ?? store.colorsOfLightsOn)
                .ignoresSafeArea()
        }
        .overlay(alignment: .bottom) {
            if let message = store.lastError {
                Toast(message: message) { store.dismissError() }
                    .padding(10)
                    .transition(.move(edge: .bottom).combined(with: .blurReplace))
            }
        }
        .clipped()
        .fontDesign(.rounded)
        .animation(Theme.softSpring, value: path)
        .animation(Theme.spring, value: store.lastError)
        .animation(Theme.softSpring, value: model.phase)
        .onChange(of: model.phase) { path = [] }
        .onChange(of: presentation.resetToken) { path = [] }
        // Esc goes back one page, or closes the panel on the home page.
        .onKeyPress(.escape) {
            if path.isEmpty {
                presentation.close()
            } else {
                isGoingBack = true
                path.removeLast()
            }
            return .handled
        }
        .onKeyPress(keys: [KeyEquivalent(",")], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            isGoingBack = false
            path = [.settings]
            return .handled
        }
    }

    @ViewBuilder
    private func page(for route: Route?) -> some View {
        let push: (Route) -> Void = { route in
            isGoingBack = false
            path.append(route)
        }
        let pop: () -> Void = {
            isGoingBack = true
            _ = path.popLast()
        }

        switch route {
        case nil:
            HomeView(push: push)
        case let .group(id):
            if let group = store.group(id) {
                GroupDetailView(group: group, push: push, pop: pop)
            } else {
                HomeView(push: push).onAppear { path = [] }
            }
        case let .light(id):
            if let light = store.lights[id] {
                LightDetailView(light: light, pop: pop)
            } else {
                HomeView(push: push).onAppear { path = [] }
            }
        case .settings:
            SettingsView(push: push, pop: pop)
        case .routines:
            RoutinesView(pop: pop)
        case .devices:
            DevicesView(pop: pop)
        case .siriCommands:
            SiriCommandsView(pop: pop)
        case .shortcuts:
            ShortcutsView(pop: pop)
        case .connection:
            ConnectionDetailsView(pop: pop)
        case .roomOrder:
            RoomOrderView(pop: pop)
        case .leftOnReminder:
            LeftOnReminderView(pop: pop)
        }
    }
}

private struct Toast: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .symbolEffect(.wiggle, options: .nonRepeating)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Schließen", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .task {
            AccessibilityNotification.Announcement(message).post()
            try? await Task.sleep(for: .seconds(5))
            onDismiss()
        }
    }
}

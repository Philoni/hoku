import SwiftUI

struct GlowSwitch: View {
    let isOn: Bool
    var tint: Color = .yellow
    var isCompact = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? AnyShapeStyle(Color.white.opacity(0.92)) : AnyShapeStyle(Theme.switchOff))
                    .frame(width: isCompact ? 30 : 36, height: isCompact ? 18 : 21)
                Circle()
                    .fill(isOn ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.white.opacity(0.9)))
                    .frame(width: isCompact ? 14 : 17, height: isCompact ? 14 : 17)
                    .shadow(color: isOn ? tint.opacity(0.9) : .black.opacity(0.25), radius: isOn ? 4 : 1.5)
                    .padding(2)
            }
            .animation(Theme.spring, value: isOn)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "Ausschalten" : "Einschalten")
        .accessibilityValue(isOn ? "An" : "Aus")
    }
}

struct SectionTitle: View {
    let text: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(text)
            Spacer()
            if let trailing { Text(trailing).opacity(0.7) }
        }
        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .padding(.top, 6)
    }
}

/// "‹ Zurück" as a small capsule: the arrow alone made people hover for the tooltip.
struct BackButton: View {
    let action: () -> Void
    @State private var bounce = 0

    var body: some View {
        Button {
            bounce += 1
            action()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .symbolEffect(.bounce, value: bounce)
                Text("Zurück")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
            }
            // The glass style pads the label itself; only nudge the chevron off the curve.
            .padding(.leading, 1)
            .padding(.trailing, 3)
            .frame(height: 26)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .help("Zurück (Esc)")
        .accessibilityLabel("Zurück")
    }
}

struct CircleIconButton: View {
    let title: String
    let systemImage: String
    var diameter: CGFloat = 26
    let action: () -> Void
    @State private var bounce = 0

    var body: some View {
        Button {
            bounce += 1
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: diameter < 26 ? 11 : 12, weight: .semibold))
                .frame(width: diameter, height: diameter)
                .symbolEffect(.bounce, value: bounce)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .help(title)
        .accessibilityLabel(title)
    }
}

/// Header with a back button for drill-down pages.
struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    let onBack: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            BackButton(action: onBack)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    // Long lamp names shrink a little before they get cut.
                    .minimumScaleFactor(0.78)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                }
            }
            Spacer()
            trailing
        }
    }
}

/// Dark rounded card background for non-slider content.
struct CardBackground: View {
    var tint: Color?

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            .fill(Theme.tile)
            .overlay {
                if let tint {
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .fill(tint.opacity(0.22).gradient)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.tileStroke, lineWidth: 1)
            )
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(Theme.spring, value: configuration.isPressed)
    }
}

/// A settings row with the same glowing switch as the light cards.
struct SettingSwitch: View {
    let title: String
    var subtitle: String?
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            GlowSwitch(isOn: isOn, tint: .orange) { isOn.toggle() }
        }
        .contentShape(Rectangle())
    }
}

/// Wrapping row of selectable chips.
struct FlowChips: View {
    let options: [(id: String, title: String)]
    let isSelected: (String) -> Bool
    let toggle: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(options, id: \.id) { option in
                let selected = isSelected(option.id)
                Button {
                    Haptics.tap()
                    toggle(option.id)
                } label: {
                    Text(option.title)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(selected ? AnyShapeStyle(Theme.selectedChipText) : AnyShapeStyle(.primary))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(selected ? AnyShapeStyle(Theme.selectedChip) : AnyShapeStyle(Theme.control)))
                }
                .buttonStyle(PressableStyle())
            }
        }
    }
}

/// Minimal flow layout: places views left to right and wraps.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, origin) in arrange(proposal: proposal, subviews: subviews).origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            width = max(width, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), origins)
    }
}

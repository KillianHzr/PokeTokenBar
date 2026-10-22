import SwiftUI

/// The popover's look in one place: rounded cards, small section titles, rounded type for titles and figures, and
/// the color of the Pokémon being raised, which tints the hero card and the selected tab.
enum Design {
    static let cornerRadius: CGFloat = 14
    static let cardPadding: CGFloat = 12
    static let sectionSpacing: CGFloat = 10
    /// The egg has no type: a warm gold until it hatches.
    static let eggColor = Color(.sRGB, red: 0.95, green: 0.72, blue: 0.30)
}

extension View {
    /// A raised card: a faint fill and a hairline border, in light and dark appearance alike.
    func designCard(padding: CGFloat = Design.cardPadding) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Design.cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: Design.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08)))
    }

    /// The hero card: the card washed with `color`, strongest behind the sprite on the left.
    func heroCard(color: Color, padding: CGFloat = Design.cardPadding) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let shape = RoundedRectangle(cornerRadius: Design.cornerRadius + 2, style: .continuous)
                shape.fill(LinearGradient(colors: [color.opacity(0.30), color.opacity(0.07)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(alignment: .topLeading) {
                        RadialGradient(colors: [color.opacity(0.45), .clear], center: .center, startRadius: 4,
                                       endRadius: 70)
                            .frame(width: 140, height: 140)
                            .offset(x: -18, y: -22)
                    }
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(color.opacity(0.35)))
            }
    }
}

/// Small uppercase title above a card's content.
@MainActor
struct SectionTitle: View {
    let text: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 9, weight: .bold)) }
            Text(text.uppercased())
        }
        .font(.system(size: 10, weight: .bold, design: .rounded))
        .tracking(0.6)
        .foregroundStyle(.secondary)
    }
}

/// A round icon button for card corners (Bonuses, recap).
@MainActor
struct CircleIconButton: View {
    let systemImage: String
    let help: String
    var tint: Color = .secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.primary.opacity(0.07)))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

extension CompanionStore {
    /// The color of the Pokémon being raised: its form's first type, gold for the egg.
    var themeColor: Color {
        guard hasActive, let id = currentSpeciesID,
              let type = PokemonTypeData.types(forSpeciesID: id, form: currentForm).first else { return Design.eggColor }
        return type.color
    }
}

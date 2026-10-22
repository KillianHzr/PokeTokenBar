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

/// A legendary Pokémon is an event: its hero card gets light rays turning behind the sprite on a golden glow,
/// twinkling stars and a holographic border going round. Animated only while the popover shows it, at a capped
/// frame rate, and still with Reduce Motion.
@MainActor
struct LegendaryHeroBackground: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let gold = Color(.sRGB, red: 1.0, green: 0.80, blue: 0.30)
    static let holo: [Color] = [gold, Color(.sRGB, red: 1.0, green: 0.45, blue: 0.70),
                                Color(.sRGB, red: 0.62, green: 0.48, blue: 1.0),
                                Color(.sRGB, red: 0.35, green: 0.80, blue: 1.0), gold]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            // Seconds into a 15 min cycle (a whole number of turns for both rotations): angles built on the absolute
            // date (8e8 s) lose their precision once drawn.
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 900)
            let shape = RoundedRectangle(cornerRadius: Design.cornerRadius + 2, style: .continuous)
            ZStack {
                shape.fill(LinearGradient(colors: [color.opacity(0.42), Self.gold.opacity(0.10), color.opacity(0.10)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                // Light rays turning behind the sprite, on a golden glow.
                AngularGradient(colors: Array(repeating: [Self.gold.opacity(0.32), .clear], count: 8).flatMap { $0 },
                                center: .center, angle: .degrees(t * 12))
                    .mask(RadialGradient(colors: [.white, .clear], center: .center, startRadius: 6, endRadius: 95))
                    .frame(width: 200, height: 200)
                    .position(x: 54, y: 52)
                RadialGradient(colors: [Self.gold.opacity(0.55), .clear], center: .center, startRadius: 2,
                               endRadius: 55)
                    .frame(width: 110, height: 110)
                    .position(x: 54, y: 52)
                sparkles(t)
            }
            .clipShape(shape)
            .overlay {
                // A gradient filled then cut to the border: a gradient stroke renders as its first color in some
                // renderers.
                AngularGradient(colors: Self.holo, center: .center, angle: .degrees(t * 40))
                    .mask(shape.strokeBorder(lineWidth: 2))
                    .shadow(color: Self.gold.opacity(0.5), radius: 5)
            }
        }
    }

    /// A few stars at fixed spots, each twinkling on its own phase.
    private func sparkles(_ t: TimeInterval) -> some View {
        GeometryReader { geo in
            let spots: [(x: CGFloat, y: CGFloat, size: CGFloat, phase: Double)] = [
                (0.08, 0.15, 9, 0), (0.30, 0.10, 6, 1.3), (0.88, 0.14, 8, 2.1), (0.95, 0.55, 6, 0.7),
                (0.62, 0.86, 7, 2.8), (0.22, 0.78, 6, 1.9), (0.75, 0.40, 5, 3.4),
            ]
            ForEach(Array(spots.enumerated()), id: \.offset) { _, spot in
                let glow = (sin(t * 2.2 + spot.phase) + 1) / 2
                Image(systemName: "sparkle")
                    .font(.system(size: spot.size, weight: .bold))
                    .foregroundStyle(Self.gold)
                    .opacity(0.25 + 0.75 * glow)
                    .scaleEffect(0.7 + 0.5 * glow)
                    .position(x: geo.size.width * spot.x, y: geo.size.height * spot.y)
            }
        }
        .allowsHitTesting(false)
    }
}

/// The "LEGENDARY" pill of a legendary hero card: gold, with a gloss.
@MainActor
struct LegendaryBadge: View {
    let text: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "crown.fill").font(.system(size: 8, weight: .bold))
            Text(text)
        }
        .font(.system(size: 9, weight: .heavy, design: .rounded))
        .foregroundStyle(Color(.sRGB, red: 0.35, green: 0.20, blue: 0.0))
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(Capsule().fill(LinearGradient(colors: [Color(.sRGB, red: 1.0, green: 0.92, blue: 0.55),
                                                           LegendaryHeroBackground.gold,
                                                           Color(.sRGB, red: 0.93, green: 0.62, blue: 0.18)],
                                                  startPoint: .top, endPoint: .bottom)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.5), lineWidth: 0.5))
        .shadow(color: LegendaryHeroBackground.gold.opacity(0.6), radius: 3)
    }
}

extension View {
    /// `heroCard`, or its legendary version for a legendary Pokémon.
    @ViewBuilder
    func heroCard(color: Color, legendary: Bool) -> some View {
        if legendary {
            self.padding(Design.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LegendaryHeroBackground(color: color))
        } else {
            heroCard(color: color)
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

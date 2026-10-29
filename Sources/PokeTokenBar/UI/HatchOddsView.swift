import SwiftUI

/// What an egg can hatch, as its roll would now (`CompanionStore.hatchOdds`): a bar of its rarities, each one named
/// with its share so that no color carries it alone, and the share of species not graduated yet.
@MainActor
struct HatchOddsView: View {
    let odds: CompanionStore.HatchOdds
    let l: L

    var body: some View {
        let shares = odds.rarities.map(\.share)
        let percents = CompanionStore.wholePercents(shares)
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                let gaps = CGFloat(max(0, shares.count - 1)) * 2
                HStack(spacing: 2) {
                    ForEach(odds.rarities.indices, id: \.self) { i in
                        rarityColor(odds.rarities[i].rarity)
                            .frame(width: max(3, (proxy.size.width - gaps) * shares[i]))
                    }
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())
            .accessibilityHidden(true)
            odds.rarities.indices.reduce(Text("")) { text, i in
                let share = odds.rarities[i]
                let separator = i == 0 ? Text("") : Text("   ")
                return text + separator
                    + Text(Image(systemName: "square.fill")).foregroundColor(rarityColor(share.rarity))
                    // Non-breaking spaces: a square never ends a line without its label.
                    + Text("\u{00A0}" + l.hatchOddsRarity(share.rarity, l.oddsPercent(percents[i], share: share.share))
                        .replacingOccurrences(of: " ", with: "\u{00A0}"))
            }
            .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
            Text(l.hatchOddsNewSpecies(l.oddsPercent(Int((odds.newSpecies * 100).rounded()), share: odds.newSpecies)))
                .font(.caption2.weight(.semibold)).monospacedDigit()
        }
        .hoverTip(l.hatchOddsHelp)
    }
}

import SwiftUI

/// A tool without limit windows pays Rare Candies by its tokens (`CompanionStore.earnTokenCandies`): how far the next
/// one is, on the tab of such a tool, as the limit rows say it for theirs. Not a limit: its bar is the candy's.
@MainActor
struct TokenCandiesCard: View {
    let store: CompanionStore

    var body: some View {
        let l = store.l
        let rate = RareCandy.tokensPerCandyWithoutLimits
        let progress = store.state.tokenCandyTokens
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: l.tokenCandiesTitle, systemImage: "circle.hexagongrid.fill")
            HStack {
                Text(l.tokenCandiesRule(TokenFormatter.compact(rate))).font(.callout)
                Spacer()
                Text("\(TokenFormatter.compact(progress)) / \(TokenFormatter.compact(rate))")
                    .font(.callout).monospacedDigit()
            }
            ProgressView(value: Double(progress), total: Double(rate))
                .tint(Color.readableOrange).controlSize(.small)
            Text(l.tokenCandiesNext(TokenFormatter.compact(rate - progress), earned: store.state.tokenCandiesEarned))
                .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
        }
        .hoverTip(l.tokenCandiesHelp)
    }
}

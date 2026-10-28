import SwiftUI

/// A Pokémon's raising record (carnet d'élevage, `RaisingRecord`) on its Pokédex page: when it hatched, how long it
/// took, its tokens by tool and its main model, their estimated cost.
@MainActor
struct RaisingRecordCard: View {
    let record: RaisingRecord
    let entry: DexEntry
    let store: CompanionStore

    /// The tools' colors, in the order of their share: none tells a tool alone, the legend names each.
    private static let palette: [Color] = [.blue, .orange, .purple, .teal, .pink, .gray]

    var body: some View {
        let l = store.l
        let providers = record.tokensByProvider.sorted { $0.value > $1.value }
        let shares = providers.map { Double($0.value) / Double(max(1, record.tokens)) }
        let percents = CompanionStore.wholePercents(shares)
        VStack(alignment: .leading, spacing: 7) {
            Text(l.raisingTitle.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded)).tracking(0.6)
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                row(l.raisingHatched, record.hatchedAt.formatted(date: .abbreviated, time: .shortened))
                if let end = entry.caughtAt {
                    let took = l.raisingTook(l.longDuration(end.timeIntervalSince(record.hatchedAt)))
                    row(entry.isReleased ? l.raisingReleased : l.raisingGraduated,
                        end.formatted(date: .abbreviated, time: .shortened) + " · " + took)
                } else {
                    row(l.raisingInProgress, l.raisingSince(l.longDuration(Date().timeIntervalSince(record.hatchedAt))))
                }
                row(l.raisingTokens, TokenFormatter.compact(record.tokens))
                if let cost = record.cost, cost > 0 { row(l.raisingCost, l.etaAbout(TokenFormatter.cost(cost))) }
                if let model = record.mainModel { row(l.raisingModel, l.raisingMostly(RaisingRecord.modelName(model))) }
            }
            .font(.caption)
            if !providers.isEmpty {
                GeometryReader { proxy in
                    let gaps = CGFloat(max(0, shares.count - 1)) * 2
                    HStack(spacing: 2) {
                        ForEach(shares.indices, id: \.self) { i in
                            Self.palette[i % Self.palette.count].frame(width: max(3, (proxy.size.width - gaps) * shares[i]))
                        }
                    }
                }
                .frame(height: 6).clipShape(Capsule()).accessibilityHidden(true)
                providers.indices.reduce(Text("")) { text, i in
                    let name = Self.toolName(providers[i].key, store: store)
                    return text + (i == 0 ? Text("") : Text("   "))
                        + Text(Image(systemName: "square.fill")).foregroundColor(Self.palette[i % Self.palette.count])
                        + Text("\u{00A0}\(name) \(l.oddsPercent(percents[i], share: shares[i]))"
                            .replacingOccurrences(of: " ", with: "\u{00A0}"))
                }
                .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Design.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Design.cornerRadius, style: .continuous).fill(Color.primary.opacity(0.045)))
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }

    /// A tool's name as the usage list shows it, or its id made readable for a tool not listed now ("Claude Code").
    static func toolName(_ id: String, store: CompanionStore) -> String {
        store.providerNames[id] ?? id.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// The catch log's short line: "1 d 19 h · 75M · mostly Claude Code".
    static func summary(_ record: RaisingRecord, entry: DexEntry, store: CompanionStore) -> String? {
        guard let end = entry.caughtAt else { return nil }
        let l = store.l
        var parts = [l.longDuration(end.timeIntervalSince(record.hatchedAt)), TokenFormatter.compact(record.tokens)]
        if let main = record.mainProvider { parts.append(l.raisingMostly(toolName(main, store: store))) }
        return parts.joined(separator: " · ")
    }
}

import XCTest
@testable import PokeTokenBar

private struct BonusProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []), rarity: .common, names: [:])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// The Home growth badge and the Bonuses page read the same factors as growth itself.
@MainActor
final class BonusOverviewTests: XCTestCase {
    private func store(active: MonState?, items: [ItemKind]) throws -> CompanionStore {
        var st = CompanionState()
        st.installBaselineSet = true
        st.lastDate = "2026-10-21"
        st.active = active
        st.inventory = Dictionary(uniqueKeysWithValues: items.map { ($0.rawValue, 1) })
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bonus-\(UUID().uuidString).json")
        try JSONEncoder().encode(st).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return CompanionStore(provider: BonusProvider(), clock: { Date(timeIntervalSince1970: 1_790_000_000) },
                              fileURL: url, rng: SeededRNG(seed: 1))
    }

    /// A repeat Tauros (no evolution, final stage) with the Magma Stone, the Sun Flute, the Relic Statue and the
    /// Old Sea Map: one badge, 2 × 4/3 × 1.25 × 1.25 × 1.2 = 5.
    func testTheGrowthBadgeCombinesTheRepeatBoostAndEveryBonus() throws {
        let tauros = MonState(baseID: 128, pathIDs: [128], stageIndex: 0, usedAtStage: 0, rarity: .common,
                              totalForms: 1, hasGrowthBoost: true)
        let s = try store(active: tauros, items: [.magmaStone, .sunFlute, .relicStatue, .oldSeaMap, .libertyPass])
        XCTAssertEqual(s.currentGrowthFactors.map(\.source),
                       [.repeatBoost, .item(.magmaStone), .item(.sunFlute), .item(.relicStatue), .item(.oldSeaMap)],
                       "the Liberty Pass is for lines never graduated")
        XCTAssertEqual(s.currentGrowthTotal, 5, accuracy: 0.0001)
        // The speed factors are the ones growth uses.
        XCTAssertEqual(s.growthSpeedMultiplier(for: tauros), 1.25 * 1.25, accuracy: 0.0001)
        XCTAssertEqual(s.currentGrowthFactors.map(s.growthFactorLine).first,
                       "\(s.l.bonusRepeat) ×\(s.l.multiplierNumber(2))")
    }

    func testAPokemonWithoutBonusShowsNoBadge() throws {
        let rattata = MonState(baseID: 19, pathIDs: [19], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 2)
        let s = try store(active: rattata, items: [.sunFlute, .magmaStone])
        XCTAssertEqual(s.currentGrowthFactors, [], "first stage, never graduated: neither applies")
        XCTAssertEqual(s.currentGrowthTotal, 1)
        XCTAssertEqual(try store(active: nil, items: [.oldSeaMap]).currentGrowthFactors, [], "an egg has no growth")
    }

    /// Token usage still counts with the same factors, in the same order.
    func testTokenGrowthUsesTheSameFactors() throws {
        let rattata = MonState(baseID: 19, pathIDs: [19], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 2)
        let s = try store(active: rattata, items: [.oldSeaMap, .dnaSplicers])
        s.applyUsage(1_000)
        XCTAssertEqual(s.state.active?.usedAtStage, Int(Double(Int(1_000 * 1.2)) * 1.5))
    }

    /// Every passive item is on the Bonuses page under one theme, without the Bag's "· active" ending.
    func testEveryPassiveItemHasAThemeAndAShortEffect() throws {
        let s = try store(active: nil, items: [])
        for kind in ItemKind.allCases {
            XCTAssertEqual(BonusTheme.of(kind) != nil, kind.isPassive, "\(kind)")
        }
        for kind in ItemKind.allCases where kind.isPassive && kind.badgeType == nil {
            let hint = s.effectHint(for: kind), effect = s.bonusEffect(for: kind)
            XCTAssertTrue(hint.hasPrefix(effect) && hint.count > effect.count, "\(kind): \(hint) / \(effect)")
            XCTAssertFalse(effect.hasSuffix(" "), "\(kind)")
        }
    }
}

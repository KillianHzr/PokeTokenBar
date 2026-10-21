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
    private func store(active: MonState?, items: [ItemKind], additive: Bool = true) throws -> CompanionStore {
        var st = CompanionState()
        st.installBaselineSet = true
        st.lastDate = "2026-10-21"
        st.active = active
        st.inventory = Dictionary(uniqueKeysWithValues: items.map { ($0.rawValue, 1) })
        st.additiveGrowthBonuses = additive
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bonus-\(UUID().uuidString).json")
        try JSONEncoder().encode(st).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return CompanionStore(provider: BonusProvider(), clock: { Date(timeIntervalSince1970: 1_790_000_000) },
                              fileURL: url, rng: SeededRNG(seed: 1))
    }

    private var tauros: MonState {
        MonState(baseID: 128, pathIDs: [128], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1,
                 hasGrowthBoost: true)
    }

    /// A repeat Tauros (no evolution, final stage) with the Magma Stone, the Sun Flute, the Relic Statue and the
    /// Old Sea Map: one badge. The bonuses add up and the repeat boost multiplies them: 2 × (1 + 1/3 + 0.25 + 0.25
    /// + 0.2) = 4.07. Multiplied together they made 5.
    func testTheGrowthBadgeCombinesTheRepeatBoostAndEveryBonus() throws {
        let s = try store(active: tauros, items: [.magmaStone, .sunFlute, .relicStatue, .oldSeaMap, .libertyPass])
        XCTAssertEqual(s.currentGrowthFactors.map(\.source),
                       [.repeatBoost, .item(.magmaStone), .item(.sunFlute), .item(.relicStatue), .item(.oldSeaMap)],
                       "the Liberty Pass is for lines never graduated")
        XCTAssertEqual(s.currentGrowthTotal, 2 * (1 + 1.0 / 3 + 0.25 + 0.25 + 0.2), accuracy: 0.0001)
        // The speed factors are the ones growth uses.
        XCTAssertEqual(s.growthSpeedMultiplier(for: tauros), 1.5, accuracy: 0.0001)
        let lines = s.currentGrowthFactors.map(s.growthFactorLine)
        XCTAssertEqual(lines.first, "\(s.l.bonusRepeat) ×\(s.l.multiplierNumber(2))")
        XCTAssertEqual(lines.last, "\(s.l.itemName(.oldSeaMap)) +\(s.l.percentNumber(20))%")
        XCTAssertEqual(s.growthSumNote(s.currentGrowthFactors),
                       s.l.bonusSumNote(s.l.percentNumber(103.333), repeatMultiplier: s.l.multiplierNumber(2)))
    }

    /// The threshold is divided by the sum of its bonuses, not their product: the Kirlia a player reported, with
    /// the Magma Stone and the Sun Flute, needs the repeat threshold / (1 + 1/3 + 0.25).
    func testTheThresholdIsDividedByTheSumOfTheBonuses() throws {
        let s = try store(active: tauros, items: [.magmaStone, .sunFlute])
        let phase = PokemonBalance.phaseThreshold(rarity: .common, totalForms: 1, stageIndex: 0, growthMultiplier: 2)
        XCTAssertEqual(s.threshold, Int((Double(phase) / (1 + 1.0 / 3 + 0.25)).rounded()))
        XCTAssertEqual(s.currentGrowthTotal, 2 * (1 + 1.0 / 3 + 0.25), accuracy: 0.0001)
        XCTAssertEqual(s.growthSumNote(s.currentGrowthFactors),
                       s.l.bonusSumNote(s.l.percentNumber(58.333), repeatMultiplier: s.l.multiplierNumber(2)))
        // One bonus alone needs no explanation, and neither does the repeat boost alone.
        XCTAssertNil(s.growthSumNote(try store(active: tauros, items: [.magmaStone]).currentGrowthFactors.dropFirst().map { $0 }))
        XCTAssertNil(s.growthSumNote(try store(active: tauros, items: []).currentGrowthFactors))
    }

    func testAPokemonWithoutBonusShowsNoBadge() throws {
        let rattata = MonState(baseID: 19, pathIDs: [19], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 2)
        let s = try store(active: rattata, items: [.sunFlute, .magmaStone])
        XCTAssertEqual(s.currentGrowthFactors, [], "first stage, never graduated: neither applies")
        XCTAssertEqual(s.currentGrowthTotal, 1)
        XCTAssertEqual(try store(active: nil, items: [.oldSeaMap]).currentGrowthFactors, [], "an egg has no growth")
    }

    /// The token items add to the other bonuses too: with the Liberty Pass (+1/3, on the threshold) and the Old Sea
    /// Map (+20%, on tokens), a token grows the Pokémon 1 + 1/3 + 0.2 times, not 4/3 × 1.2. A Rare Candy's EXP
    /// gets the threshold bonuses only, as before.
    func testTokenItemsAddToTheOtherBonuses() throws {
        let rattata = MonState(baseID: 19, pathIDs: [19], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 2)
        let both = try store(active: rattata, items: [.oldSeaMap, .dnaSplicers])
        both.applyUsage(1_000)
        XCTAssertEqual(both.state.active?.usedAtStage, 1_700, "1 + 0.2 + 0.5, not 1.2 × 1.5")
        let s = try store(active: rattata, items: [.libertyPass, .oldSeaMap])
        let phase = PokemonBalance.phaseThreshold(rarity: .common, totalForms: 2, stageIndex: 0)
        s.applyUsage(30_000)
        let grown = try XCTUnwrap(s.state.active?.usedAtStage)
        XCTAssertEqual(Double(grown) / Double(s.threshold), 30_000 * (1 + 1.0 / 3 + 0.2) / Double(phase), accuracy: 1e-6)
        s.applyUsage(1_000, isTokenUsage: false)
        XCTAssertEqual(s.state.active?.usedAtStage, grown + 1_000, "a candy's EXP is not tokens")
    }

    /// A save from when bonuses multiplied keeps its stage's progress: the threshold of a Pokémon with several
    /// bonuses goes up, and its tokens with it, once. One bonus gives the same threshold either way.
    func testASaveFromTheMultipliedRuleKeepsItsProgress() throws {
        let phase = PokemonBalance.phaseThreshold(rarity: .common, totalForms: 1, stageIndex: 0, growthMultiplier: 2)
        let old = Int((Double(phase * 3 / 4) / (1.25 * 1.25)).rounded())
        var mon = tauros
        mon.usedAtStage = old * 6 / 10
        let migrated = try store(active: mon, items: [.magmaStone, .sunFlute, .relicStatue], additive: false)
        XCTAssertTrue(migrated.state.additiveGrowthBonuses)
        XCTAssertGreaterThan(migrated.threshold, old)
        XCTAssertEqual(Double(try XCTUnwrap(migrated.state.active?.usedAtStage)) / Double(migrated.threshold), 0.6,
                       accuracy: 1e-6)
        // Already on the new rule, or one bonus: nothing moves.
        mon.usedAtStage = 12_345
        XCTAssertEqual(try store(active: mon, items: [.magmaStone, .sunFlute]).state.active?.usedAtStage, 12_345)
        XCTAssertEqual(try store(active: mon, items: [.magmaStone], additive: false).state.active?.usedAtStage, 12_345)
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

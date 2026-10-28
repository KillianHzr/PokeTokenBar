import XCTest
@testable import PokeTokenBar

private struct ArtifactProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []), rarity: .common, names: [:])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// The artifacts of the legendary and mythical Pokémon no achievement counted before: the Legend Plate's eggs, the
/// Sea Incense on those eggs, the Meteorite's candies and the groups the growth artifacts favor.
@MainActor
final class LegendaryArtifactsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func store(used: Int = 0, dex: [DexEntry] = [], active: MonState? = nil,
                       inventory: [ItemKind: Int] = [:]) throws -> CompanionStore {
        var st = CompanionState()
        st.installBaselineSet = true
        st.lastDate = "2026-10-26"
        st.usedSinceInstall = used
        st.dex = dex
        st.active = active
        st.inventory = Dictionary(uniqueKeysWithValues: inventory.map { ($0.key.rawValue, $0.value) })
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("artifacts-\(UUID().uuidString).json")
        try JSONEncoder().encode(st).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return CompanionStore(provider: ArtifactProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 1))
    }

    private func graduated(_ chain: [Int], released: Bool = false) -> DexEntry {
        DexEntry(baseID: chain[0], finalID: chain.last!, chainOrder: chain, rarity: .legendary, caughtAt: now,
                 releasedAt: released ? now : nil)
    }

    private var rattata: MonState {
        MonState(baseID: 19, pathIDs: [19], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 2)
    }

    /// Arceus's claim puts a Rare Egg and an Uncommon Egg in the Bag, once, and never the Plate itself.
    func testTheLegendPlatePutsTwoEggsInTheBag() throws {
        let s = try store(dex: [graduated([493])])
        XCTAssertTrue(s.isUnlocked(.legendPlate))
        XCTAssertTrue(s.claimAchievement(.legendPlate))
        XCTAssertEqual(s.itemCount(.rareEgg), 1)
        XCTAssertEqual(s.itemCount(.uncommonEgg), 1)
        XCTAssertEqual(s.itemCount(.legendPlate), 0, "the Plate is not an item of the Bag")
        XCTAssertTrue(s.isClaimed(.legendPlate))
        XCTAssertFalse(s.claimAchievement(.legendPlate), "claimed once")
        XCTAssertEqual(s.itemCount(.rareEgg), 1)

        // "Claim all" gives the same eggs.
        let all = try store(dex: [graduated([493])])
        XCTAssertGreaterThan(all.claimAllAchievements(), 0)
        XCTAssertEqual(all.itemCount(.rareEgg), 1)
        XCTAssertEqual(all.itemCount(.uncommonEgg), 1)
        XCTAssertTrue(all.isClaimed(.legendPlate))
    }

    /// An egg of the Bag works as the Shop's egg of its rarity, for free: the current Pokémon stays in the Pokédex.
    func testABagEggSendsThePokemonOffForAnEggOfItsRarity() throws {
        for (kind, tier) in [(ItemKind.rareEgg, Rarity.rare), (.uncommonEgg, .uncommon)] {
            let s = try store(active: rattata, inventory: [kind: 1])
            XCTAssertTrue(s.useBagEgg(kind), "\(kind)")
            XCTAssertNil(s.state.active)
            XCTAssertEqual(s.state.eggTier, tier)
            XCTAssertEqual(s.itemCount(kind), 0)
            XCTAssertEqual(s.state.spentTokens, 0, "free")
            XCTAssertEqual(s.state.dex.last?.isReleased, true, "the Pokémon sent off stays in the Pokédex")
            XCTAssertFalse(s.canUseBagEgg(kind), "an egg has no Pokémon to send off")
        }
        XCTAssertFalse(try store(active: rattata).useBagEgg(.rareEgg), "none in the Bag")
        XCTAssertFalse(try store(active: rattata, inventory: [.legendaryEgg: 1]).useBagEgg(.legendaryEgg),
                       "the Legendary Egg has its own use")
    }

    /// The Sea Incense halves the threshold of an egg of a guaranteed rarity, from the Bag or the Shop, and only those.
    func testTheSeaIncenseHatchesEggsOfAGuaranteedRarityTwiceAsFast() throws {
        let base = try store().eggHatchThreshold
        let incense = try store(active: rattata, inventory: [.rareEgg: 1, .seaIncense: 1])
        XCTAssertEqual(incense.eggHatchThreshold, base)
        XCTAssertTrue(incense.useBagEgg(.rareEgg))
        XCTAssertEqual(incense.eggHatchThreshold, base / 2)

        let shop = try store(used: 100_000_000_000, active: rattata, inventory: [.seaIncense: 1])
        XCTAssertTrue(shop.buyEgg(.uncommon))
        XCTAssertEqual(shop.eggHatchThreshold, base / 2)

        let plainEgg = try store(used: 100_000_000_000, active: rattata, inventory: [.seaIncense: 1])
        XCTAssertTrue(plainEgg.buyEgg(nil))
        XCTAssertEqual(plainEgg.eggHatchThreshold, base, "an egg without a guarantee")

        let without = try store(active: rattata, inventory: [.rareEgg: 1])
        XCTAssertTrue(without.useBagEgg(.rareEgg))
        XCTAssertEqual(without.eggHatchThreshold, base)
    }

    /// The Meteorite adds a candy to each window paid to its end, on top of the window's own candies; a window paid
    /// part of the way gets nothing extra.
    func testTheMeteoriteAddsACandyToEachWindowPaidToItsEnd() throws {
        for owned in [false, true] {
            let s = try store(inventory: owned ? [.meteorite: 1] : [:])
            let session = { (u: Double) in
                CandyWindow(key: "s", name: "T", kind: .session, utilization: u, epoch: "e", planMultiplier: 5)
            }
            s.grantCandies(from: [], limitsReady: true)
            s.grantCandiesFilling([session(40)])
            XCTAssertEqual(s.rareCandyCount, 2, "owned: \(owned)")
            s.grantCandies(from: [session(100)], limitsReady: true)
            XCTAssertEqual(s.rareCandyCount, 5 + (owned ? CollectorBonus.meteoriteWindowCandies : 0), "owned: \(owned)")
        }
    }

    /// Phione evolves into Manaphy here, so a graduated Phione counts for the Sea Incense, with Kyogre: never Manaphy
    /// alone, as no achievement but Arceus's asks for one Pokémon.
    func testPhionesLineCountsForTheSeaIncense() throws {
        XCTAssertTrue(try store(dex: [graduated([489, 490]), graduated([382])]).isUnlocked(.seaIncense))
        XCTAssertFalse(try store(dex: [graduated([489, 490])]).isUnlocked(.seaIncense), "Kyogre too")
        XCTAssertFalse(try store(dex: [graduated([489, 490], released: true), graduated([382])]).isUnlocked(.seaIncense),
                       "graduated only")
    }

    /// The Oak's Letter and the Shock Drive favor whole lines: every stage of the stones' starters, every stage of the
    /// fossils the Magma Stone counts.
    func testTheStarterAndFossilGroupsAreWholeLines() {
        func lines(endingIn finals: [Int]) -> Set<Int> {
            Set((1...1025).filter { id in
                !Set(PokemonEvolutionData.finals(from: PokemonEvolutionData.root(of: id))).isDisjoint(with: finals)
            })
        }
        let starterFinals = ItemKind.allCases.filter { $0.stoneType != nil && $0 != .shinyStone }.flatMap { kind in
            guard case .species(let goals)? = kind.unlock else { return [Int]() }
            return goals.flatMap(\.species)
        }
        XCTAssertEqual(starterFinals.count, 27)
        XCTAssertEqual(CollectorBonus.starterLines, lines(endingIn: starterFinals))
        XCTAssertEqual(CollectorBonus.fossilLines, lines(endingIn: SpeciesGoal.fossils))
    }
}


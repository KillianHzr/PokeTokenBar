import XCTest
@testable import PokeTokenBar

private struct FormProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []), rarity: .common, names: [:])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: 479, captureRate: 45)] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// The forms achievements: every form of one species graduated earns candies or eggs, and the Rotom Catalog a candy
/// for each Pokémon hatched in a form its line never had.
@MainActor
final class FormAchievementsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func store(dex: [DexEntry] = [], active: MonState? = nil, inventory: [ItemKind: Int] = [:],
                       seed: UInt64 = 1) throws -> CompanionStore {
        var st = CompanionState()
        st.installBaselineSet = true
        st.lastDate = "2026-10-27"
        st.dex = dex
        st.active = active
        st.inventory = Dictionary(uniqueKeysWithValues: inventory.map { ($0.key.rawValue, $0.value) })
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("forms-\(UUID().uuidString).json")
        try JSONEncoder().encode(st).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return CompanionStore(provider: FormProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: seed))
    }

    private func graduated(_ chain: [Int], _ form: String, released: Bool = false) -> DexEntry {
        DexEntry(baseID: chain[0], finalID: chain.last!, chainOrder: chain, rarity: .common, caughtAt: now,
                 releasedAt: released ? now : nil, form: PokemonForm(form))
    }

    private func every(_ kind: ItemKind, chain: [Int]) throws -> [DexEntry] {
        guard case .forms(let goal) = kind.unlock else { throw XCTSkip("\(kind) is no forms achievement") }
        return goal.forms.map { graduated(chain, $0.rawValue) }
    }

    /// Each achievement counts its species' forms, Minior's seven cores without its Meteor shell.
    func testEachAchievementAsksForEveryFormOfItsSpecies() {
        let expected: [(ItemKind, Int, Int)] = [(.rotomCatalog, 479, 6), (.cometShard, 774, 7), (.redNectar, 741, 4),
                                                (.smoothRock, 351, 4), (.sawsbuckSeasons, 586, 4), (.fairyFeather, 671, 5),
                                                (.furfrouTrims, 676, 10), (.vivillonPatterns, 666, 20),
                                                (.whippedDream, 869, 63), (.unownLetters, 201, 28)]
        for (kind, species, count) in expected {
            guard case .forms(let goal) = kind.unlock else { return XCTFail("\(kind)") }
            XCTAssertEqual(goal.speciesID, species, "\(kind)")
            XCTAssertEqual(goal.forms.count, count, "\(kind)")
            XCTAssertEqual(kind.collectorGroup, .forms)
        }
        guard case .forms(let minior) = ItemKind.cometShard.unlock else { return XCTFail() }
        XCTAssertFalse(minior.forms.contains(PokemonForm("meteor")))
        XCTAssertEqual(Set(ItemKind.allCases.filter { $0.collectorGroup == .forms }).count, expected.count)
    }

    /// Graduated forms only: one missing, released or being raised keeps it locked.
    func testOnlyEveryGraduatedFormUnlocksIt() throws {
        let all = try every(.redNectar, chain: [741])
        XCTAssertTrue(try store(dex: all).isUnlocked(.redNectar))
        XCTAssertFalse(try store(dex: Array(all.dropLast())).isUnlocked(.redNectar), "a style missing")
        var released = all
        released[0].releasedAt = now
        XCTAssertFalse(try store(dex: released).isUnlocked(.redNectar), "a style sent off")
        let raising = MonState(baseID: 741, pathIDs: [741], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1,
                               form: all.last!.form)
        XCTAssertFalse(try store(dex: Array(all.dropLast()), active: raising).isUnlocked(.redNectar), "a style being raised")
        XCTAssertEqual(try store(dex: Array(all.dropLast())).formProgress(FormGoal(741)).count, 3)

        // Vivillon's patterns count on Vivillon itself, whatever Scatterbug and Spewpa wore.
        XCTAssertTrue(try store(dex: try every(.vivillonPatterns, chain: [664, 665, 666])).isUnlocked(.vivillonPatterns))
    }

    /// Claimed, they put candies and eggs in the Bag, never themselves; the Rotom Catalog stays.
    func testTheirRewardsGoToTheBag() throws {
        let rewards: [(ItemKind, [Int], [ItemKind: Int])] = [
            (.cometShard, [774], [.rareCandy: 5]), (.redNectar, [741], [.rareCandy: 3]), (.smoothRock, [351], [.rareCandy: 3]),
            (.sawsbuckSeasons, [585, 586], [.uncommonEgg: 1]), (.fairyFeather, [669, 670, 671], [.uncommonEgg: 1]),
            (.furfrouTrims, [676], [.rareEgg: 1]), (.vivillonPatterns, [664, 665, 666], [.rareEgg: 2]),
            (.whippedDream, [868, 869], [.rareEgg: 2, .rareCandy: 5]), (.unownLetters, [201], [.rareEgg: 2]),
        ]
        for (kind, chain, items) in rewards {
            let s = try store(dex: try every(kind, chain: chain))
            XCTAssertTrue(s.isUnlocked(kind), "\(kind)")
            XCTAssertTrue(s.claimAchievement(kind), "\(kind)")
            for (item, count) in items { XCTAssertEqual(s.itemCount(item), count, "\(kind) gives \(item)") }
            XCTAssertEqual(s.itemCount(kind), 0, "\(kind) is not kept")
            XCTAssertTrue(s.isClaimed(kind))
            XCTAssertFalse(s.claimAchievement(kind), "once")
        }
        let rotom = try store(dex: try every(.rotomCatalog, chain: [479]))
        XCTAssertTrue(rotom.claimAchievement(.rotomCatalog))
        XCTAssertEqual(rotom.itemCount(.rotomCatalog), 1)
        XCTAssertEqual(BonusTheme.of(.rotomCatalog), .candies)
    }

    /// The Rotom Catalog pays one candy for a Pokémon hatched in a form its line never had, none for a form it had.
    func testTheRotomCatalogPaysForANewForm() async throws {
        let heat = graduated([479], "heat")
        for (owned, expected) in [(1, 1), (0, 0)] {
            let s = try store(dex: [heat], inventory: owned > 0 ? [.rotomCatalog: 1] : [:])
            await s.hatch(baseID: 479)
            let mon = try XCTUnwrap(s.state.active)
            XCTAssertEqual(s.itemCount(.rareCandy), mon.hasNewForm ? expected : 0, "form \(String(describing: mon.form))")
        }
        // Over seeds, both a new form (a candy) and the known Heat Rotom (none) come.
        var paid = Set<Bool>()
        for seed: UInt64 in 1...24 {
            let s = try store(dex: [heat], inventory: [.rotomCatalog: 1], seed: seed)
            await s.hatch(baseID: 479)
            let mon = try XCTUnwrap(s.state.active)
            XCTAssertEqual(s.itemCount(.rareCandy), mon.form == PokemonForm("heat") ? 0 : 1, "seed \(seed)")
            paid.insert(s.itemCount(.rareCandy) > 0)
        }
        XCTAssertEqual(paid, [true, false])
    }
}

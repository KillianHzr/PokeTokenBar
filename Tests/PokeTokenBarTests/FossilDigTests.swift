import XCTest
@testable import PokeTokenBar

private struct FossilProvider: PokeProviding {
    var entries: [BaseSpecies] = FossilDig.lines.map { BaseSpecies(id: $0, captureRate: 45) } + [BaseSpecies(id: 1, captureRate: 45)]
    var indexDown = false
    struct Down: Error {}
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []),
                rarity: entries.first { $0.id == baseSpeciesID }?.rarity ?? .common, names: [:])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] {
        if indexDown { throw Down() }
        return entries
    }
    func baseSpecies(id: Int) async throws -> BaseSpecies? {
        indexDown ? BaseSpecies(id: id, captureRate: 45) : entries.first { $0.id == id }
    }
}

/// The excavation: a Fossil Egg for every 4 Rock-type species graduated, one dig per fossil line, the lines graduated
/// some other way counting as dug; a Fossil Egg hatches a fossil line still missing, at random.
@MainActor
final class FossilDigTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func store(dex: [DexEntry] = [], inventory: [ItemKind: Int] = [:], seed: UInt64 = 1, indexDown: Bool = false,
                       _ edit: (inout CompanionState) -> Void = { _ in }) throws -> CompanionStore {
        var st = CompanionState()
        st.installBaselineSet = true
        st.lastDate = "2026-10-27"
        st.dex = dex
        st.inventory = Dictionary(uniqueKeysWithValues: inventory.map { ($0.key.rawValue, $0.value) })
        edit(&st)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fossil-\(UUID().uuidString).json")
        try JSONEncoder().encode(st).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return CompanionStore(provider: FossilProvider(indexDown: indexDown), clock: { self.now }, fileURL: url,
                              rng: SeededRNG(seed: seed))
    }

    private func graduated(_ id: Int, form: String? = nil) -> DexEntry {
        DexEntry(baseID: id, finalID: id, chainOrder: [id], rarity: .common, caughtAt: now, form: form.map { PokemonForm($0) })
    }

    /// Rock species that are not fossils, so graduating them never counts a fossil line as dug.
    private var rocks: [Int] {
        let fossilSpecies = CollectorBonus.fossilLines
        return FossilDig.rockSpecies.filter { !fossilSpecies.contains($0) && !PokemonForm.hasForms(speciesID: $0) }
    }

    func testFifteenDigsEachFourMoreRockPokemon() {
        XCTAssertEqual(FossilDig.lines.count, 15)
        XCTAssertEqual(SpeciesGoal.fossils.count, FossilDig.lines.count, "one line per fossil final")
        let goals = ItemKind.excavation.regionGoals ?? []
        XCTAssertEqual(goals.map(\.generation), Array(1...15))
        XCTAssertEqual(goals.map(\.goal.needed), (1...15).map { $0 * 4 })
        XCTAssertGreaterThanOrEqual(FossilDig.rockSpecies.count, 60, "enough Rock species for every dig")
        XCTAssertTrue(FossilDig.rockSpecies.contains(59), "Hisuian Arcanine is Rock")
        XCTAssertEqual(ItemKind.excavation.collectorGroup, .evolutionStones)
        XCTAssertNil(ItemKind.fossilEgg.shopPrice)
    }

    /// Four Rock species graduated: the first dig gives a Fossil Egg, once.
    func testADigGivesAFossilEgg() throws {
        let s = try store(dex: rocks.prefix(9).map { graduated($0) })
        let tiers = s.regionTiers(.excavation)
        XCTAssertEqual(tiers.filter(\.isReady).map(\.generation), [1, 2])
        XCTAssertTrue(s.claimAchievement(.excavation))
        XCTAssertEqual(s.itemCount(.fossilEgg), 2)
        XCTAssertEqual(s.itemCount(.excavation), 0, "the dig itself is not an item")
        XCTAssertFalse(s.claimAchievement(.excavation), "the third dig needs 12")
        XCTAssertEqual(s.regionTiers(.excavation).filter(\.isClaimed).count, 2)
    }

    /// A Rock form counts its species: a Hisuian Growlithe and Arcanine, not a Kanto one.
    func testARockFormCounts() throws {
        func arcanine(_ form: String?) -> DexEntry {
            DexEntry(baseID: 58, finalID: 59, chainOrder: [58, 59], rarity: .common, caughtAt: now,
                     form: form.map { PokemonForm($0) })
        }
        let hisui = try store(dex: [arcanine("hisui")])
        XCTAssertTrue(hisui.rockSpeciesGraduated.isSuperset(of: [58, 59]))
        let kanto = try store(dex: [arcanine(nil)])
        XCTAssertTrue(kanto.rockSpeciesGraduated.isDisjoint(with: [58, 59]))
    }

    /// Fossil lines graduated some other way count as dug: the last digs are done with nothing to claim, so the eggs
    /// to claim match the lines missing. Lines hatched from Fossil Eggs do not.
    func testLinesAlreadyGraduatedCountAsDug() throws {
        let owned = [138, 140, 142].map { graduated($0) }
        let s = try store(dex: owned + rocks.prefix(60).map { graduated($0) })
        let tiers = s.regionTiers(.excavation)
        XCTAssertEqual(tiers.filter(\.isWaived).map(\.generation), [13, 14, 15])
        XCTAssertEqual(tiers.filter(\.isReady).count, 12, "one egg per line still missing")
        XCTAssertEqual(s.claimRegionTiers(.excavation), 12)
        XCTAssertEqual(s.itemCount(.fossilEgg), 12)
        XCTAssertTrue(s.isClaimed(.excavation), "every dig done")

        let hatched = try store(dex: owned + rocks.prefix(12).map { graduated($0) }) { $0.fossilEggsHatched = 3 }
        XCTAssertEqual(hatched.regionTiers(.excavation).filter(\.isWaived).count, 0, "those came from Fossil Eggs")
    }

    /// What the card tells: the eggs left to dig once the lines had before take theirs away, the ones dug and ready,
    /// and the Rock-type Pokémon the next one still wants out of 4.
    func testTheCardCountsTheEggsAndTheRockPokemonTowardTheNext() throws {
        // Omanyte and Kabuto, had before the digs and Rock themselves, plus 9 more Rock: 11 in all.
        let s = try store(dex: [138, 140].map { graduated($0) } + rocks.prefix(9).map { graduated($0) }) {
            $0.claimedAchievements = [CompanionState.regionTierKey(.excavation, generation: 1)]
        }
        let progress = s.excavationProgress
        XCTAssertEqual(progress.digs.count, 13, "15 digs, 2 lines already had")
        XCTAssertEqual(progress.waived, 2)
        XCTAssertEqual(progress.dug, 1)
        XCTAssertEqual(progress.ready, 1, "8 Rock reached, not claimed yet")
        XCTAssertEqual(progress.towardNext, 3, "the third egg wants 12: 11 is 3 of its 4")
        XCTAssertEqual(progress.linesGraduated, 2)

        let every = try store(dex: FossilDig.lines.map { graduated($0) }).excavationProgress
        XCTAssertTrue(every.digs.isEmpty, "every line already had: no egg to dig")
        XCTAssertNil(every.towardNext)
        XCTAssertEqual(try store().excavationProgress.towardNext, 0, "nothing yet: 0 of 4")
    }

    /// A Fossil Egg hatches a missing fossil line, each as likely; once every line graduated, any of them.
    func testAFossilEggHatchesAMissingLine() async throws {
        let owned = FossilDig.lines.dropFirst(2).map { graduated($0) }   // Omanyte and Kabuto missing
        var hatched = Set<Int>()
        for seed: UInt64 in 1...10 {
            let s = try store(dex: Array(owned), inventory: [.fossilEgg: 1], seed: seed) {
                $0.active = MonState(baseID: 1, pathIDs: [1], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
            }
            XCTAssertTrue(s.useFossilEgg())
            XCTAssertEqual(s.eggKind, .fossil)
            s.setEggUsageForTesting(s.eggHatchThreshold)
            await s.hatchIfNeeded()
            let mon = try XCTUnwrap(s.state.active, "seed \(seed)")
            XCTAssertTrue([138, 140].contains(mon.baseID), "seed \(seed): \(mon.baseID)")
            XCTAssertFalse(s.state.eggFromFossilEgg)
            XCTAssertEqual(s.state.fossilEggsHatched, 1)
            hatched.insert(mon.baseID)
        }
        XCTAssertEqual(hatched, [138, 140], "both missing lines come")

        let all = try store(dex: FossilDig.lines.map { graduated($0) }, inventory: [.fossilEgg: 1]) {
            $0.active = MonState(baseID: 1, pathIDs: [1], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
        }
        XCTAssertTrue(all.useFossilEgg())
        all.setEggUsageForTesting(all.eggHatchThreshold)
        await all.hatchIfNeeded()
        XCTAssertTrue(FossilDig.lines.contains(try XCTUnwrap(all.state.active).baseID), "every line graduated: any of them")
    }

    /// The base index down, the REST fallback keeps to the fossil lines.
    func testTheRestFallbackKeepsToFossils() async throws {
        var hatched = 0
        for seed: UInt64 in 1...12 {
            let s = try store(inventory: [.fossilEgg: 1], seed: seed, indexDown: true) {
                $0.active = MonState(baseID: 1, pathIDs: [1], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
            }
            XCTAssertTrue(s.useFossilEgg())
            s.setEggUsageForTesting(s.eggHatchThreshold)
            await s.hatchIfNeeded()
            guard let mon = s.state.active else { continue }   // no fossil among the tries: the egg waits
            hatched += 1
            XCTAssertTrue(FossilDig.lines.contains(mon.baseID), "seed \(seed): \(mon.baseID)")
        }
        XCTAssertGreaterThan(hatched, 0)
    }

    /// A fossil line not graduated yet hatches from Fossil Eggs only: a plain egg, a rarity's egg, a stone's egg or an
    /// event's never brings one, nor does the REST fallback.
    func testFossilLinesHatchFromFossilEggsOnly() async throws {
        func hatch(seed: UInt64, indexDown: Bool = false, _ edit: (inout CompanionState) -> Void = { _ in }) async throws -> Int? {
            let s = try store(seed: seed, indexDown: indexDown, edit)
            s.setEggUsageForTesting(s.eggHatchThreshold)
            await s.hatchIfNeeded()
            return s.state.active?.baseID
        }
        for seed: UInt64 in 1...8 {
            let plain = try await hatch(seed: seed)
            XCTAssertEqual(plain, 1, "a plain egg: seed \(seed)")
            let rare = try await hatch(seed: seed) { $0.eggTier = .rare }
            XCTAssertEqual(rare, 1, "a Rare Egg: seed \(seed)")
            // Omanyte, Kabuto, Tirtouga and Dracovish are Water: a Water Stone's egg has no other candidate here.
            let water = try await hatch(seed: seed) { $0.eggTypeGuarantee = .water }
            XCTAssertNil(water, "no fossil for a Water Stone's egg: it waits")
            let kanto = try await hatch(seed: seed) { $0.eggEvent = .pokemonDay }
            XCTAssertEqual(kanto, 1, "Pokémon Day's Kanto pool without Omanyte, Kabuto, Aerodactyl")
            if let rest = try await hatch(seed: seed, indexDown: true) {
                XCTAssertFalse(FossilDig.isFossilLine(rest), "the REST fallback: seed \(seed)")
            }
        }
    }

    /// Once graduated, a fossil line hatches from any egg like every other species: a Water Stone's egg brings the
    /// Omanyte already graduated, never Kabuto, Tirtouga or Dracovish, still missing.
    func testAGraduatedFossilLineJoinsEveryEgg() async throws {
        var plain: Set<Int> = []
        for seed: UInt64 in 1...16 {
            let water = try store(dex: [graduated(138)], seed: seed) { $0.eggTypeGuarantee = .water }
            water.setEggUsageForTesting(water.eggHatchThreshold)
            await water.hatchIfNeeded()
            XCTAssertEqual(water.state.active?.baseID, 138, "seed \(seed)")

            let egg = try store(dex: [graduated(138)], seed: seed)
            egg.setEggUsageForTesting(egg.eggHatchThreshold)
            await egg.hatchIfNeeded()
            plain.insert(try XCTUnwrap(egg.state.active).baseID)
        }
        XCTAssertEqual(plain, [1, 138], "a plain egg: Bulbasaur or Omanyte, never a fossil line still missing")
    }

    func testTheSaveKeepsTheDigs() throws {
        var st = CompanionState()
        st.eggFromFossilEgg = true
        st.fossilEggsHatched = 4
        let kept = try JSONDecoder().decode(CompanionState.self, from: JSONEncoder().encode(st))
        XCTAssertTrue(kept.eggFromFossilEgg)
        XCTAssertEqual(kept.fossilEggsHatched, 4)
        st.active = MonState(baseID: 1, pathIDs: [1], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
        XCTAssertFalse(SaveTransfer.sanitized(st).eggFromFossilEgg, "no egg beside a Pokémon being raised")
        XCTAssertEqual(SaveTransfer.sanitized(st).fossilEggsHatched, 4)
    }
}

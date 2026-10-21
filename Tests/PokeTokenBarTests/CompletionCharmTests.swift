import XCTest
@testable import PokeTokenBar

private struct CharmProvider: PokeProviding {
    let entries = [BaseSpecies(id: 1, captureRate: 45), BaseSpecies(id: 201, captureRate: 225)]
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []), rarity: .common, names: [:])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { entries }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { entries.first { $0.id == id } }
}

/// Completing the Pokédex earns two charms: every species the Oval Charm (eggs bring the forms still missing),
/// every form the Glimmering Charm (every hatch is shiny).
@MainActor
final class CompletionCharmTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_000_000)

    /// A record of one species; its base is its line's, which a form needs to be kept (Alolan Raichu: Pichu).
    private func entry(_ id: Int, _ form: PokemonForm? = nil) -> DexEntry {
        DexEntry(baseID: PokemonForm.lineBase(of: id), finalID: id, chainOrder: [id], rarity: .common,
                 caughtAt: date, form: form)
    }

    /// One entry per species, or per form of a species with forms.
    private var everyForm: [DexEntry] {
        PokemonAssets.animatedSpeciesIDs.flatMap { id -> [DexEntry] in
            let forms = PokemonForm.forms(speciesID: id)
            return forms.isEmpty ? [entry(id)] : forms.map { entry(id, $0) }
        }
    }

    private func store(dex: [DexEntry], items: [ItemKind] = [], seed: UInt64 = 1) throws -> CompanionStore {
        var st = CompanionState()
        st.installBaselineSet = true
        st.lastDate = "2026-10-21"
        st.dex = dex
        st.inventory = Dictionary(uniqueKeysWithValues: items.map { ($0.rawValue, 1) })
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("charms-\(UUID().uuidString).json")
        try JSONEncoder().encode(st).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let s = CompanionStore(provider: CharmProvider(), clock: { self.date }, fileURL: url, rng: SeededRNG(seed: seed))
        s.setEggUsageForTesting(s.eggHatchThreshold)
        return s
    }

    func testEverySpeciesUnlocksTheOvalCharm() throws {
        XCTAssertTrue(try store(dex: (1...1025).map { entry($0) }).isUnlocked(.ovalCharm))
        XCTAssertFalse(try store(dex: (1...1024).map { entry($0) }).isUnlocked(.ovalCharm))
    }

    func testEveryFormUnlocksTheGlimmeringCharm() throws {
        let all = try store(dex: everyForm)
        XCTAssertEqual(all.collectionProgress.forms, CompanionStore.collectableFormCount)
        XCTAssertTrue(all.isUnlocked(.glimmeringCharm))
        let missingOne = everyForm.filter { !($0.finalID == 201 && $0.form == PokemonForm("question")) }
        XCTAssertFalse(try store(dex: missingOne).isUnlocked(.glimmeringCharm))
    }

    /// Every Unown letter but "?": the charm hatches Unown, and only as "?".
    func testTheOvalCharmHatchesOnlyFormsStillMissing() async throws {
        let owned = Set(PokemonForm.forms(speciesID: 201).filter { $0 != PokemonForm("question") })
        var bulbasaurWithout = false
        for seed: UInt64 in 1...16 {
            let s = try store(dex: owned.map { entry(201, $0) }, items: [.ovalCharm], seed: seed)
            await s.hatchIfNeeded()
            XCTAssertEqual(s.state.active?.baseID, 201, "seed \(seed): Bulbasaur has no form to bring")
            XCTAssertEqual(s.state.active?.form, PokemonForm("question"), "seed \(seed)")
            let plain = try store(dex: owned.map { entry(201, $0) }, seed: seed)
            await plain.hatchIfNeeded()
            if plain.state.active?.baseID == 1 { bulbasaurWithout = true }
        }
        XCTAssertTrue(bulbasaurWithout, "without the charm Bulbasaur still hatches")
    }

    /// With nothing left to bring, eggs roll as usual.
    func testTheOvalCharmStepsAsideOnceNothingIsMissing() async throws {
        var bulbasaur = false
        for seed: UInt64 in 1...24 {
            let s = try store(dex: PokemonForm.forms(speciesID: 201).map { entry(201, $0) }, items: [.ovalCharm], seed: seed)
            await s.hatchIfNeeded()
            if s.state.active?.baseID == 1 { bulbasaur = true }
        }
        XCTAssertTrue(bulbasaur)
    }

    func testTheGlimmeringCharmMakesEveryHatchShinyWithoutShiftingTheOtherRolls() async throws {
        for seed: UInt64 in 1...8 {
            let charm = try store(dex: [], items: [.glimmeringCharm], seed: seed)
            await charm.hatchIfNeeded()
            XCTAssertEqual(charm.currentIsShiny, true, "seed \(seed)")
            let plain = try store(dex: [], seed: seed)
            await plain.hatchIfNeeded()
            XCTAssertEqual(charm.state.active?.baseID, plain.state.active?.baseID, "seed \(seed)")
            XCTAssertEqual(charm.currentNature, plain.currentNature, "seed \(seed)")
        }
    }
}

import XCTest
@testable import PokeTokenBar

/// Vulpix is the only candidate: Fire in its default form, Ice in its Alolan form.
private struct VulpixOnlyProvider: PokeProviding {
    let entries = [BaseSpecies(id: 37, captureRate: 190)]
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []), rarity: .common,
                names: [baseSpeciesID: ["en": "Vulpix"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { entries }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { entries.first { $0.id == id } }
}

/// A stone egg guarantees the type of the Pokémon that hatches, regional form included.
@MainActor
final class StoneEggFormTests: XCTestCase {
    private let alola = PokemonForm("alola")

    private func egg(_ type: PokemonType, seed: UInt64) -> CompanionStore {
        var st = CompanionState()
        st.installBaselineSet = true
        st.lastDate = "2026-10-20"
        st.eggTypeGuarantee = type
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("stone-form-\(UUID().uuidString).json")
        try? JSONEncoder().encode(st).write(to: url)
        return CompanionStore(provider: VulpixOnlyProvider(), clock: { Date(timeIntervalSince1970: 1_790_000_000) },
                              fileURL: url, rng: SeededRNG(seed: seed))
    }

    /// Both hatch paths: the form pre-rolled with the species (`hatchIfNeeded`), and the form rolled at
    /// hatch time after the guarantee is consumed (`hatch(baseID:)`).
    private func hatchBothWays(_ type: PokemonType, seed: UInt64) async -> [CompanionStore] {
        let prerolled = egg(type, seed: seed)
        prerolled.setEggUsageForTesting(prerolled.eggHatchThreshold)
        await prerolled.hatchIfNeeded()
        let direct = egg(type, seed: seed)
        await direct.hatch(baseID: 37)
        return [prerolled, direct]
    }

    func testFireStoneEggNeverHatchesAnAlolanVulpix() async {
        for seed: UInt64 in 0..<24 {
            for s in await hatchBothWays(.fire, seed: seed) {
                XCTAssertEqual(s.state.active?.baseID, 37, "seed \(seed)")
                XCTAssertNotEqual(s.state.active?.form, alola, "an Alolan Vulpix is Ice, seed \(seed)")
            }
        }
    }

    func testIceStoneEggHatchesVulpixInItsAlolanForm() async {
        for seed: UInt64 in 0..<24 {
            for s in await hatchBothWays(.ice, seed: seed) {
                XCTAssertEqual(s.state.active?.baseID, 37, "Vulpix is an Ice candidate through its Alolan form")
                XCTAssertEqual(s.state.active?.form, alola, "seed \(seed)")
            }
        }
    }

    func testFormTypesOverrideTheSpeciesTypes() {
        XCTAssertEqual(PokemonTypeData.types(forSpeciesID: 37, form: nil), [.fire])
        XCTAssertEqual(PokemonTypeData.types(forSpeciesID: 37, form: alola), [.ice])
        XCTAssertEqual(PokemonTypeData.types(forSpeciesID: 479, form: PokemonForm("heat")), [.electric, .fire])
        XCTAssertEqual(PokemonTypeData.types(forSpeciesID: 493, form: PokemonForm("fire")), [.fire])
        XCTAssertTrue(PokemonTypeData.canHatch(baseID: 37, as: .ice))
        XCTAssertFalse(PokemonTypeData.canHatch(baseID: 37, as: .ice, form: PokemonForm("normal")))
        XCTAssertFalse(PokemonTypeData.canHatch(baseID: 4, as: .ice), "Charmander has no Ice form")
    }

    /// Every id in the form table belongs to a form the app knows, so a typo cannot hide behind the fallback.
    func testFormTypesOnlyListKnownForms() {
        var known = Set<Int>()
        for id in PokemonAssets.animatedSpeciesIDs {
            for form in PokemonForm.forms(speciesID: id) {
                if let formID = PokemonForm.formID(speciesID: id, form: form) { known.insert(formID) }
            }
        }
        XCTAssertEqual(Set(PokemonTypeData.formTypes.keys).subtracting(known), [])
    }
}

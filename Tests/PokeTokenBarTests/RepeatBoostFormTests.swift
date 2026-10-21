import XCTest
@testable import PokeTokenBar

/// Diglett line: Kanto by default, Alolan in its `alola` form.
private struct DiglettProvider: PokeProviding {
    let entries = [BaseSpecies(id: 50, captureRate: 255)]
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 50, tree: EvoNode(speciesID: 50, children: [EvoNode(speciesID: 51, children: [])]),
                rarity: .common, names: [50: ["en": "Diglett"], 51: ["en": "Dugtrio"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { entries }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { entries.first { $0.id == id } }
}

/// The repeat growth boost ("Growth ×2") is for an appearance already in the Pokédex. It was decided per line,
/// so a first Alolan Dugtrio got it because a Kanto Dugtrio had graduated.
@MainActor
final class RepeatBoostFormTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_000_000)
    private let alola = PokemonForm("alola")
    private let normal = PokemonForm("normal")

    /// Hatches a Diglett pre-rolled in `form`, after the given graduated and released Dugtrio.
    private func hatch(_ form: PokemonForm, graduated: [PokemonForm?], released: [PokemonForm] = [],
                       lostRecord: Bool = false) async throws -> MonState {
        var st = CompanionState()
        st.installBaselineSet = true
        st.lastDate = "2026-10-21"
        st.dex = graduated.map {
            DexEntry(baseID: 50, finalID: 51, chainOrder: [50, 51], rarity: .common, caughtAt: date, form: $0)
        } + released.map {
            DexEntry(baseID: 50, finalID: 50, chainOrder: [50], rarity: .common, caughtAt: date, releasedAt: date, form: $0)
        }
        st.collectedFinals = graduated.isEmpty && !lostRecord ? [] : ["50:51"]
        st.pendingHatchID = 50
        st.pendingForm = form
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("repeat-form-\(UUID().uuidString).json")
        try JSONEncoder().encode(st).write(to: url)
        let s = CompanionStore(provider: DiglettProvider(), clock: { self.date }, fileURL: url, rng: SeededRNG(seed: 1))
        s.setEggUsageForTesting(s.eggHatchThreshold)
        await s.hatchIfNeeded()
        let active = try XCTUnwrap(s.state.active)
        XCTAssertEqual(active.form, form)
        return active
    }

    func testRepeatBoostNeedsTheSameFormGraduated() async throws {
        let firstAlolan = try await hatch(alola, graduated: [normal])
        XCTAssertFalse(firstAlolan.hasGrowthBoost, "a first Alolan Dugtrio is new even after a Kanto one")
        let secondKanto = try await hatch(normal, graduated: [normal])
        XCTAssertTrue(secondKanto.hasGrowthBoost)
        let secondAlolan = try await hatch(alola, graduated: [normal, alola])
        XCTAssertTrue(secondAlolan.hasGrowthBoost)
        let beforeForms = try await hatch(normal, graduated: [nil])
        XCTAssertTrue(beforeForms.hasGrowthBoost, "records from before forms existed are the default form")
        let releasedOnly = try await hatch(alola, graduated: [], released: [alola])
        XCTAssertFalse(releasedOnly.hasGrowthBoost, "a released Alolan Diglett never graduated")
        let lostRecord = try await hatch(normal, graduated: [], lostRecord: true)
        XCTAssertTrue(lostRecord.hasGrowthBoost, "a graduation missing from the Pokédex still counts for the line")
    }
}

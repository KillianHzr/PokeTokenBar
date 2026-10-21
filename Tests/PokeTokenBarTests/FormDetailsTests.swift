import XCTest
@testable import PokeTokenBar

/// Answers each PokéAPI variety with its own data and records which ones were asked for: a Kanto Vulpix (37) has
/// Flash Fire and Ember, an Alolan one (10103) Snow Cloak and Powder Snow.
private actor VulpixProvider: PokeProviding, PokemonDetailProviding {
    private var requested: [Int] = []

    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 37, tree: EvoNode(speciesID: 37, children: [EvoNode(speciesID: 38, children: [])]),
                rarity: .common, names: [37: ["en": "Vulpix"], 38: ["en": "Ninetales"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        try await pokemonDetails(pokemonID: speciesID, speciesID: speciesID)
    }
    func pokemonDetails(pokemonID: Int, speciesID: Int) async throws -> PokemonDetails {
        requested.append(pokemonID)
        let alolan = pokemonID == 10103
        return PokemonDetails(speciesID: speciesID, name: alolan ? "vulpix-alola" : "vulpix", height: 6, weight: 99,
                              baseExperience: 60, genderRate: 6, types: [alolan ? "ice" : "fire"],
                              baseStats: ["hp": 38, "special-attack": 50],
                              abilities: [PokemonAbilityOption(name: alolan ? "snow-cloak" : "flash-fire", slot: 1,
                                                               isHidden: false)],
                              moves: [PokemonMoveOption(name: alolan ? "powder-snow" : "ember",
                                                        learnMethods: [PokemonMoveLearnMethod(method: "level-up", level: 1)])])
    }
    func requestedIDs() -> [Int] { requested }
}

/// A form is its own Pokémon: its stats, ability, size and moves come from its PokéAPI variety, never from its
/// default form. They used to: an Alolan Vulpix had Flash Fire and a Kanto Vulpix's stats.
@MainActor
final class FormDetailsTests: XCTestCase {
    private let alola = PokemonForm("alola")
    private let date = Date(timeIntervalSince1970: 1_790_000_000)

    private func store(_ st: CompanionState, provider: VulpixProvider) throws -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("form-details-\(UUID().uuidString).json")
        try JSONEncoder().encode(st).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return CompanionStore(provider: provider, clock: { self.date }, fileURL: url, rng: SeededRNG(seed: 1))
    }

    /// A profile saved with the default form's ability, as every Alolan Vulpix was.
    private func savedWithKantoData() -> PokemonProfile {
        var profile = PokemonProfile.generate(seed: 7)
        profile.gender = .female
        profile.abilitySlot = 1
        profile.abilityName = "flash-fire"
        profile.moves = [PokemonKnownMove(name: "ember", learnedAtLevel: 1)]
        return profile
    }

    func testAFormReadsItsOwnVarietyAndFixesItsSavedIndividuals() async throws {
        var st = CompanionState()
        st.installBaselineSet = true
        st.lastDate = "2026-10-21"
        st.active = MonState(baseID: 37, pathIDs: [37], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 2,
                             profile: savedWithKantoData(), form: alola)
        st.dex = [DexEntry(baseID: 37, finalID: 37, chainOrder: [37], rarity: .common, caughtAt: date,
                           profile: savedWithKantoData(), releasedAt: date)]
        let provider = VulpixProvider()
        let s = try store(st, provider: provider)

        await s.loadPokemonDetails(speciesID: 37, form: alola)
        let requestedAlola = await provider.requestedIDs()
        XCTAssertEqual(requestedAlola, [10103], "the Alolan variety, not the species")
        XCTAssertEqual(s.pokemonDetails(speciesID: 37, form: alola)?.name, "vulpix-alola")
        XCTAssertNil(s.pokemonDetails(speciesID: 37, form: nil), "the Kanto data is another resource")
        let profile = try XCTUnwrap(s.state.active?.profile)
        XCTAssertEqual(profile.abilityName, "snow-cloak", "same slot, its own form's ability")
        XCTAssertEqual(profile.abilitySlot, 1)
        XCTAssertEqual(profile.moves.map(\.name), ["powder-snow"])
        XCTAssertEqual(profile.gender, .female, "what was rolled stays")
        XCTAssertEqual(s.state.dex[0].profile?.abilityName, "flash-fire", "a Kanto Vulpix keeps a Kanto Vulpix's")

        await s.loadPokemonDetails(speciesID: 37, form: nil)
        let requestedBoth = await provider.requestedIDs()
        XCTAssertEqual(requestedBoth, [10103, 37])
        XCTAssertEqual(s.state.active?.profile?.abilityName, "snow-cloak", "Kanto data never reaches the Alolan one")
    }

    /// The hatch fills the profile once its form is rolled: an Alolan Vulpix hatches with Snow Cloak at once.
    func testAFormHatchesWithItsOwnAbility() async throws {
        var st = CompanionState()
        st.installBaselineSet = true
        st.lastDate = "2026-10-21"
        st.pendingHatchID = 37
        st.pendingForm = alola
        let s = try store(st, provider: VulpixProvider())
        await s.loadPokemonDetails(speciesID: 37, form: alola)
        s.setEggUsageForTesting(s.eggHatchThreshold)
        await s.hatchIfNeeded()
        let active = try XCTUnwrap(s.state.active)
        XCTAssertEqual(active.form, alola)
        XCTAssertEqual(active.profile?.abilityName, "snow-cloak")
    }

    /// An Alolan Vulpix is missing from Black 2 and White 2, its species' games: its moves come from the first game
    /// that has it. Before, it had no moves at all.
    func testARegionalFormLearnsItsMovesFromItsOwnGames() {
        func row(_ group: String) -> PokemonMoveVersionDTO {
            PokemonMoveVersionDTO(level_learned_at: 1, move_learn_method: NamedRef(name: "level-up", url: nil),
                                  version_group: NamedRef(name: group, url: nil))
        }
        let moves = [PokemonMoveDTO(move: NamedRef(name: "powder-snow", url: nil),
                                    version_group_details: [row("sword-shield"), row("ultra-sun-ultra-moon")]),
                     PokemonMoveDTO(move: NamedRef(name: "tail-whip", url: nil),
                                    version_group_details: [row("scarlet-violet")])]
        XCTAssertEqual(PokeAPIClient.normalizedMoves(moves, for: 37).map(\.name), ["powder-snow"])
        XCTAssertEqual(PokemonForm.detailsID(speciesID: 37, form: alola), 10103)
        XCTAssertEqual(PokemonForm.detailsID(speciesID: 37, form: nil), 37)
        XCTAssertEqual(PokemonForm.detailsID(speciesID: 201, form: PokemonForm("b")), 201, "Unown's letters are looks")
    }
}

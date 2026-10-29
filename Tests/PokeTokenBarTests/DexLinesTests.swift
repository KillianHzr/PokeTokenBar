import XCTest
@testable import PokeTokenBar

private struct NoLines: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// The Pokédex counts evolution lines too: one family from its first species, with a Pokémon graduated.
@MainActor
final class DexLinesTests: XCTestCase {
    private func store(_ dex: [DexEntry]) throws -> CompanionStore {
        var state = CompanionState()
        state.installBaselineSet = true
        state.dex = dex
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lines-\(UUID().uuidString).json")
        try JSONEncoder().encode(state).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return CompanionStore(provider: NoLines(), fileURL: url)
    }

    private func entry(_ chain: [Int], released: Bool = false) -> DexEntry {
        DexEntry(baseID: chain[0], finalID: chain.last!, chainOrder: chain, rarity: .common, caughtAt: nil,
                 releasedAt: released ? Date() : nil)
    }

    /// A Pikachu raised without its Pichu is Pichu's line; a released Pokémon's line is seen, not graduated.
    func testALineIsOneFamilyWithAGraduatedPokemon() throws {
        let s = try store([entry([1, 2, 3]), entry([25, 26]), entry([172]), entry([4, 5], released: true)])
        XCTAssertEqual(s.graduatedCollectionProgress.lines, 2, "Bulbasaur's, and Pichu's for Pikachu and Pichu")
        XCTAssertEqual(s.collectionProgress.lines, 3, "Charmander's seen only")
        XCTAssertEqual(PokemonEvolutionData.root(of: 26), 172)
    }

    /// Every line of the 1,025 species: one per species that evolves from none.
    func testEveryLineIsCountedOnce() throws {
        let total = CompanionStore.evolutionLineCount
        XCTAssertEqual(total, PokemonAssets.animatedSpeciesIDs.filter { PokemonEvolutionData.parents[$0] == nil }.count)
        XCTAssertTrue((400...600).contains(total), "\(total)")
        XCTAssertEqual(try store([]).graduatedCollectionProgress.linesTotal, total)
    }
}

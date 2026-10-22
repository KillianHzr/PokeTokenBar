import XCTest
@testable import PokeTokenBar

private struct DexCoverProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// A Pokédex species caught shiny used to open on its latest catch: a normal Vulpix caught after a shiny one opened
/// the page in normal colors, and a species with forms always showed its default form in normal colors in the grid.
/// `dexCover` is what both show first now.
@MainActor
final class DexCoverTests: XCTestCase {
    private let kanto = PokemonForm("normal")
    private let alola = PokemonForm("alola")

    /// Vulpix caught in these forms, oldest first.
    private func store(_ catches: [(form: PokemonForm, shiny: Bool)]) throws -> CompanionStore {
        let suite = "DexCover-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        var state = CompanionState()
        state.language = .en
        state.installBaselineSet = true
        state.dex = catches.enumerated().map { index, item in
            DexEntry(baseID: 37, finalID: 37, chainOrder: [37], rarity: .common,
                     caughtAt: Date(timeIntervalSince1970: 1_790_000_000 + Double(index)),
                     isShiny: item.shiny, names: [37: ["en": "Vulpix"]], form: item.form)
        }
        try JSONEncoder().encode(state).write(to: file)
        return CompanionStore(provider: DexCoverProvider(), fileURL: file, defaults: defaults)
    }

    private func cover(_ store: CompanionStore) throws -> CompanionStore.DexSpecies {
        store.dexCover(for: try XCTUnwrap(store.dexSpecies.first { $0.id == 37 }))
    }

    func testAShinyFormComesFirstEvenAfterANormalCatch() throws {
        // The shiny Alolan Vulpix was caught first; the Kanto one, normal, is the latest catch and the default form.
        let store = try store([(alola, true), (kanto, false)])
        let cover = try cover(store)
        XCTAssertEqual(cover.form, alola)
        XCTAssertTrue(cover.isShiny)
    }

    func testTheRepresentativeComesFirstWhenShinyOrWhenNoFormIsShiny() throws {
        let both = try store([(kanto, true), (alola, true)])
        XCTAssertTrue(both.setRepresentativeSpeciesID(37, form: alola))
        XCTAssertEqual(try cover(both).form, alola, "a shiny representative before the default form")

        let normalRepresentative = try store([(kanto, true), (alola, false)])
        XCTAssertTrue(normalRepresentative.setRepresentativeSpeciesID(37, form: alola))
        XCTAssertEqual(try cover(normalRepresentative).form, kanto, "a shiny form before a normal representative")

        let noShiny = try store([(kanto, false), (alola, false)])
        XCTAssertEqual(try cover(noShiny).form, kanto, "the first collected form")
        XCTAssertTrue(noShiny.setRepresentativeSpeciesID(37, form: alola))
        XCTAssertEqual(try cover(noShiny).form, alola, "the representative without a shiny form")
        XCTAssertFalse(try cover(noShiny).isShiny)
    }

    func testOnlyFormCollectedIsTheCoverNotTheDefaultForm() throws {
        let store = try store([(alola, false)])
        XCTAssertEqual(try cover(store).form, alola, "a Kanto Vulpix was never caught")
    }

    func testASpeciesWithoutFormsIsItsOwnCover() throws {
        let suite = "DexCoverPlain-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
        defer { try? FileManager.default.removeItem(at: file) }
        var state = CompanionState()
        state.dex = [true, false].enumerated().map { index, shiny in
            DexEntry(baseID: 606, finalID: 606, chainOrder: [606], rarity: .common,
                     caughtAt: Date(timeIntervalSince1970: 1_790_000_000 + Double(index)), isShiny: shiny)
        }
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: DexCoverProvider(), fileURL: file, defaults: defaults)
        let species = try XCTUnwrap(store.dexSpecies.first)
        let cover = store.dexCover(for: species)
        XCTAssertEqual(cover.collectionID, species.collectionID)
        XCTAssertTrue(cover.isShiny, "caught shiny before a normal one")
    }
}

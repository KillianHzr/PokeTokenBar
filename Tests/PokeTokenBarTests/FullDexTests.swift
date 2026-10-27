import XCTest
@testable import PokeTokenBar

/// The whole Pokédex (TokenDex's view): every species region by region, the missing ones alone when asked, and a
/// search by number or by the name of a species already caught.
@MainActor
final class FullDexTests: XCTestCase {
    private let names = [25: "Pikachu", 133: "Eevee"]

    func testEverySpeciesShowsAndTheMissingOnesAlone() {
        let all = (1...1025).filter { FullDexView.shows($0, names: names, missingOnly: false, query: "") }
        XCTAssertEqual(all.count, 1025, "species not caught show too")
        let missing = (1...1025).filter { FullDexView.shows($0, names: names, missingOnly: true, query: "") }
        XCTAssertEqual(missing.count, 1023)
        XCTAssertFalse(missing.contains(25))
        XCTAssertEqual(PokemonTypeData.generations.reduce(0) { $0 + $1.count }, 1025, "the regions cover the Pokédex")
    }

    func testTheSearchFindsANumberOrACaughtName() {
        func found(_ query: String) -> [Int] {
            (1...1025).filter { FullDexView.shows($0, names: names, missingOnly: false, query: query) }
        }
        XCTAssertEqual(found("#025"), [25, 250, 251, 252, 253, 254, 255, 256, 257, 258, 259])
        XCTAssertTrue(found("1025").contains(1025))
        XCTAssertEqual(found("pika"), [25])
        XCTAssertEqual(found("EEV"), [133])
        XCTAssertEqual(found("bulbasaur"), [], "a name is known once the species is caught")
    }

    /// Shiny only, in All: the species caught shiny and no other.
    func testTheShinyFilterKeepsTheSpeciesCaughtShiny() {
        XCTAssertEqual(FullDexView.visibleIDs(names: names, missingOnly: false, query: "", shinies: [133]), [133])
        XCTAssertEqual(FullDexView.visibleIDs(names: names, missingOnly: false, query: "pika", shinies: [133]), [],
                       "the search and the filter both apply")
    }

    /// The family filter brings the whole line of what the search finds, its missing members too; Missing keeps those.
    func testTheFamilyFilterBringsTheWholeLineMissingMembersIncluded() {
        let caught = [4: "Charmander", 133: "Eevee"]
        XCTAssertEqual(FullDexView.visibleIDs(names: caught, missingOnly: false, query: "charm"), [4])
        XCTAssertEqual(FullDexView.visibleIDs(names: caught, missingOnly: false, query: "charm", family: true), [4, 5, 6])
        XCTAssertEqual(FullDexView.visibleIDs(names: caught, missingOnly: true, query: "charm", family: true), [5, 6],
                       "Missing: Charmeleon and Charizard")
        XCTAssertEqual(Set(FullDexView.family(of: 134)), [133, 134, 135, 136, 196, 197, 470, 471, 700],
                       "a branching line, from any of its members")
        XCTAssertEqual(FullDexView.visibleIDs(names: caught, missingOnly: false, query: "", family: true).count, 1025,
                       "no search: nothing to widen")
    }
}

import XCTest
@testable import PokeTokenBar

private struct NoLines: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// The Shop says more (6.3): the base price struck when an item lowers it and why, the Shiny Charm's odds, several
/// eggs bought at once.
@MainActor
final class ShopClarityTests: XCTestCase {
    private func store(_ edit: (inout CompanionState) -> Void) throws -> CompanionStore {
        var state = CompanionState()
        state.installBaselineSet = true
        state.usedSinceInstall = 2_000_000_000
        edit(&state)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shop-\(UUID().uuidString).json")
        try JSONEncoder().encode(state).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return CompanionStore(provider: NoLines(), fileURL: url)
    }

    func testDiscountsAreNamedAndTheBasePriceKept() throws {
        let plain = try store { _ in }
        XCTAssertEqual(plain.discounts(of: .egg(nil)), [])
        XCTAssertEqual(plain.basePrice(of: .egg(nil)), plain.price(of: .egg(nil)))

        let both = try store { $0.inventory = [ItemKind.rainbowWing.rawValue: 1, ItemKind.jadeOrb.rawValue: 1] }
        XCTAssertEqual(both.discounts(of: .egg(nil)), [.rainbowWing, .jadeOrb])
        XCTAssertEqual(both.discounts(of: .item(.rareCandy)), [.rainbowWing], "the Jade Orb lowers eggs only")
        XCTAssertEqual(both.basePrice(of: .egg(nil)), plain.price(of: .egg(nil)))
        XCTAssertLessThan(both.price(of: .egg(nil)), both.basePrice(of: .egg(nil)))
    }

    func testTheShinyCharmShowsItsOdds() throws {
        XCTAssertTrue(try store { _ in }.shinyCharmOdds == (64, 48))
        XCTAssertTrue(try store { $0.inventory = [ItemKind.revealGlass.rawValue: 1] }.shinyCharmOdds == (32, 24))
    }

    func testSeveralEggsAreBoughtAtOnce() throws {
        let s = try store { _ in }
        let price = s.price(of: .egg(nil))
        let most = s.maxEggBuyCount(nil)
        XCTAssertEqual(most, s.availableTokens / price)
        XCTAssertTrue(s.buyEgg(nil, count: 3))
        XCTAssertEqual(s.itemCount(.pokemonEgg), 3)
        XCTAssertFalse(s.buyEgg(nil, count: s.maxEggBuyCount(nil) + 1), "never more than the wallet")
        XCTAssertFalse(s.buyEgg(nil, count: 0))
    }
}

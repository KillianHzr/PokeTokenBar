import XCTest
@testable import PokeTokenBar

/// The hatch index is cached for 30 days. One cached before the Gen 6 to 9 range existed stopped at #649, and
/// it kept every later Pokémon out of eggs until it expired: only Gen 1 to 5 species and their forms hatched.
final class BaseIndexCacheRangeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let entries = [BaseSpecies(id: 1, captureRate: 45)]

    private func snapshot(ageDays: Double, maxSpeciesID: Int?) -> PokeAPIClient.BaseIndexSnapshot {
        PokeAPIClient.BaseIndexSnapshot(fetchedAt: now.addingTimeInterval(-ageDays * 86400), entries: entries,
                                        maxSpeciesID: maxSpeciesID)
    }

    func testOnlyARecentIndexOfTheCurrentRangeIsReused() {
        let current = PokemonAssets.animatedSpeciesIDs.upperBound
        XCTAssertTrue(PokeAPIClient.isFreshBaseIndex(snapshot(ageDays: 1, maxSpeciesID: current), now: now))
        XCTAssertFalse(PokeAPIClient.isFreshBaseIndex(snapshot(ageDays: 1, maxSpeciesID: 649), now: now),
                       "an index from before Gen 6 to 9 is refetched")
        XCTAssertFalse(PokeAPIClient.isFreshBaseIndex(snapshot(ageDays: 1, maxSpeciesID: nil), now: now),
                       "a snapshot written before the field existed stopped at #649")
        XCTAssertFalse(PokeAPIClient.isFreshBaseIndex(snapshot(ageDays: 31, maxSpeciesID: current), now: now))
    }

    /// The user's cache had this shape: no `maxSpeciesID` key. It still decodes, so it stays available as the
    /// offline fallback, but it is never reused as fresh.
    func testAnIndexWrittenWithoutTheRangeStillDecodes() throws {
        let json = #"{"fetchedAt":782000000,"entries":[{"id":1,"captureRate":45,"isUnbreedableLegendary":false}]}"#
        let decoded = try JSONDecoder().decode(PokeAPIClient.BaseIndexSnapshot.self, from: Data(json.utf8))
        XCTAssertNil(decoded.maxSpeciesID)
        XCTAssertEqual(decoded.entries.map(\.id), [1])
    }
}

import XCTest
@testable import PokeTokenBar

/// The "New form" badge (#61): a Pokémon that hatched in a form its line never had says so on Home while it grows,
/// and its catch log entry keeps saying so once it graduates or is sent off.
@MainActor
final class NewFormBadgeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    /// Vulpix into Ninetales, Kanto or Alolan.
    private let line = EvoLine(baseID: 37, tree: EvoNode(speciesID: 37, children: [EvoNode(speciesID: 38, children: [])]),
                               rarity: .common, names: [:])

    private func store(seed: UInt64 = 5, _ edit: (inout CompanionState) -> Void = { _ in }) throws -> CompanionStore {
        var st = CompanionState()
        st.installBaselineSet = true
        st.lastDate = "2026-10-26"
        edit(&st)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("newform-\(UUID().uuidString).json")
        try JSONEncoder().encode(st).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return CompanionStore(provider: StubProvider(value: line), clock: { self.now }, fileURL: url,
                              rng: SeededRNG(seed: seed))
    }

    /// The first Vulpix brings its form: the growing one and then its graduated entry say so; the next Vulpix in the
    /// same form doesn't.
    func testTheFlagFollowsTheIndividualIntoTheCatchLog() async throws {
        let s = try store()
        await s.hatch(baseID: 37)
        let form = try XCTUnwrap(s.state.active?.form)
        XCTAssertEqual(s.state.active?.hasNewForm, true)
        XCTAssertEqual(s.dexEntries.last?.hasNewForm, true, "the growing one's row in the catch log")
        s.applyUsage(s.threshold)
        s.applyUsage(s.threshold)
        let graduated = try XCTUnwrap(s.state.dex.last)
        XCTAssertEqual(graduated.finalID, 38)
        XCTAssertTrue(graduated.hasNewForm)

        await s.hatch(baseID: 37)
        let second = try XCTUnwrap(s.state.active)
        XCTAssertEqual(second.hasNewForm, second.form != form, "\(form) is in the Pokédex now")
        let kept = try JSONDecoder().decode(CompanionState.self, from: JSONEncoder().encode(s.state))
        XCTAssertEqual(kept.dex.last?.hasNewForm, true)
    }

    /// Sent off before graduating, it keeps the flag too.
    func testASentOffPokemonKeepsTheFlag() async throws {
        let s = try store { $0.inventory[ItemKind.legendaryEgg.rawValue] = 1 }
        await s.hatch(baseID: 37)
        XCTAssertEqual(s.state.active?.hasNewForm, true)
        XCTAssertTrue(s.useLegendaryEgg())
        let released = try XCTUnwrap(s.state.dex.last)
        XCTAssertTrue(released.isReleased)
        XCTAssertTrue(released.hasNewForm)
    }

    /// Entries saved before the flag was kept read as not new.
    func testOlderEntriesReadAsNotNew() throws {
        let entry = DexEntry(baseID: 37, finalID: 38, chainOrder: [37, 38], rarity: .common, caughtAt: now)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        json.removeValue(forKey: "hasNewForm")
        let read = try JSONDecoder().decode(DexEntry.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(read.hasNewForm)
    }
}

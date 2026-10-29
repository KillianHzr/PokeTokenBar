import XCTest
@testable import PokeTokenBar

private struct OddsProvider: PokeProviding {
    let entries: [BaseSpecies]
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []), rarity: .common, names: [:])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { entries }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { entries.first { $0.id == id } }
}

/// The odds an egg card shows (`CompanionStore.hatchOdds`): the roll's own pool and weights, in whole percents
/// that add up to 100.
@MainActor
final class HatchOddsTests: XCTestCase {
    /// Two commons (one graduated), an uncommon, a rare and a legendary: weights 212, 212, 90, 40 and 3.
    private let entries = [BaseSpecies(id: 19, captureRate: 255), BaseSpecies(id: 16, captureRate: 255),
                           BaseSpecies(id: 37, captureRate: 100), BaseSpecies(id: 1, captureRate: 45),
                           BaseSpecies(id: 144, captureRate: 3, isUnbreedableLegendary: true)]

    private func store() async throws -> CompanionStore {
        var st = CompanionState()
        st.installBaselineSet = true
        st.lastDate = "2026-10-28"
        st.dex = [DexEntry(baseID: 19, finalID: 19, chainOrder: [19], rarity: .common, caughtAt: Date())]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("odds-\(UUID().uuidString).json")
        try JSONEncoder().encode(st).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let s = CompanionStore(provider: OddsProvider(entries: entries), clock: Date.init, fileURL: url)
        await s.loadHatchIndex()
        return s
    }

    func testOddsAreTheRollsWeights() async throws {
        let s = try await store()
        let plain = try XCTUnwrap(s.hatchOdds(for: .init()))
        XCTAssertEqual(plain.rarities.map(\.rarity), [.common, .uncommon, .rare, .legendary])
        XCTAssertEqual(plain.rarities.map(\.share), [424, 90, 40, 3].map { Double($0) / 557 })
        XCTAssertEqual(plain.newSpecies, 345.0 / 557, accuracy: 1e-12, "all but the graduated Rattata")
        XCTAssertEqual(CompanionStore.wholePercents(plain.rarities.map(\.share)), [76, 16, 7, 1])

        let uncommon = try XCTUnwrap(s.hatchOdds(for: .init(tier: .uncommon)))
        XCTAssertEqual(uncommon.rarities.map(\.rarity), [.uncommon, .rare, .legendary], "no Common from it")
        XCTAssertEqual(uncommon.rarities.map(\.share), [90, 40, 3].map { Double($0) / 133 })
        XCTAssertEqual(try XCTUnwrap(s.hatchOdds(for: .init(legendaryEgg: true))).rarities.map(\.rarity), [.legendary])
        XCTAssertEqual(CompanionStore.EggSpec(item: .rareEgg), .init(tier: .rare))
        XCTAssertEqual(CompanionStore.EggSpec(item: .pokemonEgg), .init())
        XCTAssertEqual(CompanionStore.EggSpec(item: .fireStone), .init(type: .fire))
        XCTAssertNil(CompanionStore.EggSpec(item: .birthdayEgg), "its own roll")
    }

    /// Rounded one by one, 78.5, 11.1, 9.3 and 1.1 make 99: the largest remainders take what is missing.
    func testWholePercentsAddUpTo100() {
        for shares in [[0.785, 0.111, 0.093, 0.011], [0.7612, 0.1616, 0.0718, 0.0054], [1 / 3.0, 1 / 3.0, 1 / 3.0],
                       [0.515, 0.433, 0.052], [0.999, 0.001], [1.0]] {
            XCTAssertEqual(CompanionStore.wholePercents(shares).reduce(0, +), 100, "\(shares)")
        }
        XCTAssertEqual(CompanionStore.wholePercents([0.999, 0.001]), [100, 0])
    }

    /// A share that rounds to none reads "<1", one short of all ">99"; French puts its spaces.
    func testTinySharesAreNotShownAsNoneOrAll() {
        let en = L(.en), fr = L(.fr)
        XCTAssertEqual(en.oddsPercent(0, share: 0.001), "<1%")
        XCTAssertEqual(en.oddsPercent(100, share: 0.999), ">99%")
        XCTAssertEqual(en.oddsPercent(100, share: 1), "100%")
        XCTAssertEqual(en.oddsPercent(45, share: 0.45), "45%")
        XCTAssertEqual(fr.oddsPercent(0, share: 0.001), "< 1 %")
        XCTAssertEqual(fr.oddsPercent(45, share: 0.45), "45 %")
    }
}

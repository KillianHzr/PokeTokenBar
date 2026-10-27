import XCTest
@testable import PokeTokenBar

private struct OneDifficultyProvider: PokeProviding {
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: [
            EvoNode(speciesID: 2, children: [EvoNode(speciesID: 3, children: [])])]),
                rarity: .common, names: [:])
    }
}

/// One difficulty for every player (`PokemonBalance.difficulty`): the growth and shop sliders are gone. A save made at
/// a slider's value keeps the fraction of its egg or stage, once, and the sliders' values are removed.
@MainActor
final class OneDifficultyTests: XCTestCase {
    private func fixture(egg: Bool = false, slider: Double? = nil, boost: Bool = false)
        throws -> (store: CompanionStore, url: URL, defaults: UserDefaults) {
        var state = CompanionState()
        state.installBaselineSet = true
        state.lastDate = "2026-10-27"
        state.claimedTodayTokensByProvider = ["test": 1234]
        state.usedSinceInstall = 900_000_000
        state.spentTokens = 123_000_000
        let at = slider ?? PokemonBalance.difficulty
        if egg {
            state.eggUsage = Int(Double(PokemonBalance.eggHatchThreshold) * at * 0.5)
        } else {
            var mon = MonState(baseID: 1, pathIDs: [1], plannedPathIDs: [1, 2, 3], stageIndex: 0, usedAtStage: 0,
                               rarity: .common, totalForms: 3, hasGrowthBoost: boost)
            mon.usedAtStage = Int(Double(mon.phaseThreshold) * at * 0.5)
            state.active = mon
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("one-difficulty-\(UUID()).json")
        try JSONEncoder().encode(state).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let suite = "one-difficulty-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        if let slider {
            defaults.set(slider, forKey: "growthDifficulty")
            defaults.set(slider, forKey: "shopDifficulty")
        }
        let store = CompanionStore(provider: OneDifficultyProvider(), fileURL: url, dittoDisguiseRollingEnabled: false,
                                   defaults: defaults)
        return (store, url, defaults)
    }

    /// Thresholds and prices are the tables at the one difficulty; Rare Candies keep their full EXP.
    func testThresholdsAndPricesUseTheOneDifficulty() async throws {
        XCTAssertEqual(PokemonBalance.difficulty, 0.1)
        let s = try fixture().store
        XCTAssertEqual(s.eggHatchThreshold, PokemonBalance.scaled(PokemonBalance.eggHatchThreshold, by: 0.1))
        XCTAssertEqual(s.eggHatchThreshold, 500_000)
        let mon = try XCTUnwrap(s.state.active)
        XCTAssertEqual(s.threshold, PokemonBalance.scaled(mon.phaseThreshold, by: 0.1))
        XCTAssertEqual(s.price(of: .item(.rareCandy)), PokemonBalance.scaled(RareCandy.price, by: 0.1))
        XCTAssertEqual(s.price(of: .egg(.rare)), PokemonBalance.scaled(FreshEgg.price(guaranteeing: .rare), by: 0.1))
        XCTAssertEqual(s.rareCandyXP, RareCandy.xp)
        for language in AppLanguage.allCases {
            let hint = L(language).eggFirstRunHint(TokenFormatter.compact(s.eggHatchThreshold))
            XCTAssertTrue(hint.contains("500K"), "\(language.rawValue): \(hint)")
        }
    }

    /// A save made at a slider's value, including the 5% a local build allowed, keeps the fraction of its egg or stage,
    /// once: the sliders' values are removed, and a restart moves nothing. Tokens used and the wallet never move.
    func testASliderOfAPreviousReleaseKeepsTheProgressFractionOnce() throws {
        for slider in [1.0, 0.05, 2.0, 0.0001, 20.0] {
            for egg in [false, true] {
                for boost in [false, true] where !(egg && boost) {
                    let (s, url, defaults) = try fixture(egg: egg, slider: slider, boost: boost)
                    XCTAssertEqual(egg ? s.eggProgress : s.progress, 0.5, accuracy: 0.000_01, "\(slider) egg: \(egg)")
                    XCTAssertNil(defaults.object(forKey: "growthDifficulty"))
                    XCTAssertNil(defaults.object(forKey: "shopDifficulty"))
                    XCTAssertEqual(s.state.usedSinceInstall, 900_000_000)
                    XCTAssertEqual(s.state.spentTokens, 123_000_000)
                    XCTAssertEqual(s.state.claimedTodayTokensByProvider, ["test": 1234])

                    let again = CompanionStore(provider: OneDifficultyProvider(), fileURL: url,
                                               dittoDisguiseRollingEnabled: false, defaults: defaults)
                    XCTAssertEqual(again.state.active?.usedAtStage, s.state.active?.usedAtStage)
                    XCTAssertEqual(again.state.eggUsage, s.state.eggUsage)
                }
            }
        }
    }

    /// Without a saved slider (a new install, or a save already moved) the progress stays as it is.
    func testWithoutASavedSliderNothingMoves() throws {
        for egg in [false, true] {
            let s = try fixture(egg: egg).store
            XCTAssertEqual(egg ? s.eggProgress : s.progress, 0.5, accuracy: 0.000_01)
        }
    }

    /// No threshold nor price falls to zero at the one difficulty: the smallest table value is the 5M egg.
    func testNothingCollapsesToZero() async throws {
        XCTAssertGreaterThan(PokemonBalance.scaled(PokemonBalance.eggHatchThreshold), 0)
        for rarity in [Rarity.common, .uncommon, .rare, .legendary] {
            for k in 1...3 {
                for i in 0..<k {
                    let t = PokemonBalance.scaled(PokemonBalance.phaseThreshold(rarity: rarity, totalForms: k, stageIndex: i))
                    XCTAssertGreaterThan(t, 0, "rarity=\(rarity) k=\(k) i=\(i)")
                }
            }
        }
        let s = try fixture().store
        for entry in s.shopEntries { XCTAssertGreaterThan(s.price(of: entry), 0, "\(entry)") }
    }
}

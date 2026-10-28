import XCTest
@testable import PokeTokenBar

private struct SingleStageProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []), rarity: .rare,
                names: [baseSpeciesID: ["en": "P\(baseSpeciesID)"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: 4, captureRate: 45)] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// The candies of tools without limits, the raising record, the time to the next stage and the three items that
/// grow a Pokémon (Silver Wing, Tera Orb, Sea Incense).
@MainActor
final class RaisingAndTokenCandyTests: XCTestCase {
    private let day = "2026-10-28"

    private func store(_ edit: (inout CompanionState) -> Void = { _ in }) throws -> CompanionStore {
        var st = CompanionState()
        st.installBaselineSet = true
        st.lastDate = day
        st.claimedTodayTokensByProvider = ["claude_code": 0, "cursor": 0]
        edit(&st)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("raising-\(UUID().uuidString).json")
        try JSONEncoder().encode(st).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return CompanionStore(provider: SingleStageProvider(), clock: Date.init, fileURL: url)
    }

    private func refresh(_ s: CompanionStore, _ tokens: [String: Int]) {
        s.update(todayTokensByProvider: tokens, todayDate: day, monthTotal: tokens.values.reduce(0, +), burnTier: .idle,
                 limitWarning: false, hasUsageData: true)
    }

    /// A tool with no limit window pays a candy every 65M tokens, keeping the rest; one with a window (Claude here,
    /// in the candy ledger) is paid by it and never by its tokens.
    func testToolsWithoutLimitsPayCandiesByTokens() throws {
        let s = try store { $0.candyWindowPlan = ["claude.152146ba.sevenDay": 5] }
        XCTAssertFalse(s.paysCandiesByTokens("claude_code"))
        XCTAssertTrue(s.paysCandiesByTokens("cursor"))
        let rate = RareCandy.tokensPerCandyWithoutLimits
        refresh(s, ["claude_code": 500_000_000, "cursor": 40_000_000])
        XCTAssertEqual(s.rareCandyCount, 0, "Claude's tokens pay nothing here, Cursor's 40M not yet a candy")
        refresh(s, ["claude_code": 500_000_000, "cursor": 40_000_000 + rate])
        XCTAssertEqual(s.rareCandyCount, 1)
        XCTAssertEqual(s.state.tokenCandyTokens, 40_000_000, "the rest waits for the next one")
        XCTAssertEqual(s.state.tokenCandiesEarned, 1)
        refresh(s, ["claude_code": 500_000_000, "cursor": 40_000_000 + 3 * rate])
        XCTAssertEqual(s.rareCandyCount, 3)
        XCTAssertEqual(CandyWindow.providerID(forKey: "codex.codex.primary"), "codex")
        XCTAssertEqual(CandyWindow.providerID(forKey: "antigravity.gemini.5h"), "antigravity")
    }

    /// The raising record starts at the hatch, adds each refresh's tokens by tool, spreads them over the day's
    /// models and prices them at the day's cost, and goes with the Pokémon into the Pokédex.
    func testTheRaisingRecordFollowsThePokemon() async throws {
        let s = try store { $0.inventory = [ItemKind.rareCandy.rawValue: 1] }
        await s.hatch(baseID: 4)
        let hatched = try XCTUnwrap(s.state.active?.raising)
        XCTAssertEqual(hatched.tokens, 0)
        s.todayUsageDetails = ["claude_code": TodayUsageDetail(tokens: 1_000, cost: 10,
                                                              models: ["claude-opus-5-5": 750, "claude-haiku-5-5": 250]),
                               "cursor": TodayUsageDetail(tokens: 400, cost: nil, models: [:])]
        refresh(s, ["claude_code": 1_000, "cursor": 400])
        let record = try XCTUnwrap(s.state.active?.raising)
        XCTAssertEqual(record.tokensByProvider, ["claude_code": 1_000, "cursor": 400])
        XCTAssertEqual(record.tokensByModel, ["claude-opus-5-5": 750, "claude-haiku-5-5": 250])
        XCTAssertEqual(try XCTUnwrap(record.cost), 10, accuracy: 1e-9)
        XCTAssertEqual(record.mainProvider, "claude_code")
        XCTAssertEqual(RaisingRecord.modelName(try XCTUnwrap(record.mainModel)), "Opus 5.5")
        XCTAssertEqual(s.dexEntries.last?.raising, record, "the Pokédex shows the one being raised")

        _ = s.useRareCandy()
        XCTAssertEqual(s.state.active?.raising?.candiesUsed ?? s.state.dex.last?.raising?.candiesUsed, 1, "a candy used on it")
        s.applyUsage(100_000_000_000)
        XCTAssertNil(s.state.active)
        XCTAssertEqual(s.state.dex.last?.raising?.tokensByProvider, record.tokensByProvider, "kept at the graduation")
        XCTAssertEqual(s.state.dex.last?.raising?.candiesUsed, 1)
        // A record written before a field existed keeps the rest.
        let old = try JSONDecoder().decode(RaisingRecord.self, from: Data(#"{"hatchedAt":0,"tokensByProvider":{"codex":5}}"#.utf8))
        XCTAssertEqual(old.tokensByProvider, ["codex": 5])
        XCTAssertEqual(old.candiesUsed, 0)
        XCTAssertEqual(RaisingRecord.modelName("claude-sonnet-4-5-20250929"), "Sonnet 4.5")
        XCTAssertEqual(RaisingRecord.modelName("gpt-5-codex"), "gpt-5-codex")
    }

    /// The time to the next stage: the tokens left at the user's pace, the token bonuses taken off.
    func testTheTimeToTheNextStageFollowsThePace() async throws {
        let s = try store()
        await s.hatch(baseID: 4)
        XCTAssertNil(s.timeToNext, "no pace yet")
        s.usagePacePerDay = Double(s.tokensNeededToNext) * 2
        XCTAssertEqual(try XCTUnwrap(s.timeToNext), 43_200, accuracy: 1, "half a day")
        let l = L(.en)
        XCTAssertEqual(CompanionHeader.trackCaption([.reached(4, isCurrent: true), .graduation], amount: "95M", percent: "24%",
                                                    names: [:], l: l, eta: l.etaAbout("9h")),
                       "\(l.toGraduation("95M")) · 24% · about 9h")
    }

    /// Silver Wing grows every Pokémon 25% faster; Tera Orb a stone's Pokémon 30%; Sea Incense one from an egg of a
    /// guaranteed rarity 30%. An event egg's type or rarity is the event's: neither.
    func testTheEggItemsGrowWhatCameFromTheirEggs() async throws {
        let items: [String: Int] = [ItemKind.silverWing.rawValue: 1, ItemKind.teraOrb.rawValue: 1,
                                    ItemKind.seaIncense.rawValue: 1]
        func factors(_ edit: @escaping (inout CompanionState) -> Void) async throws -> [ItemKind] {
            let s = try store {
                $0.inventory = items
                edit(&$0)
            }
            await s.hatch(baseID: 4)
            let mon = try XCTUnwrap(s.state.active)
            return s.growthSpeedFactors(for: mon).compactMap { if case .item(let kind) = $0.source { kind } else { nil } }
        }
        let plain = try await factors { _ in }
        XCTAssertTrue(plain.contains(.silverWing))
        XCTAssertFalse(plain.contains(.teraOrb))
        XCTAssertFalse(plain.contains(.seaIncense))
        let stone = try await factors { $0.eggTypeGuarantee = .fire }
        XCTAssertTrue(stone.contains(.teraOrb), "a stone's egg")
        let rare = try await factors { $0.eggTier = .rare }
        XCTAssertTrue(rare.contains(.seaIncense), "a Rare Egg")
        XCTAssertEqual(CollectorBonus.silverWingGrowth, 1.25)
        XCTAssertEqual(CollectorBonus.teraOrbStoneGrowth, 1.3)
        XCTAssertEqual(CollectorBonus.seaIncenseRarityEggGrowth, 1.3)
    }
}

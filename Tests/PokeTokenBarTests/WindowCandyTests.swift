import XCTest
@testable import PokeTokenBar

private struct WCClaude: ClaudeLimitsProviding {
    var status: LimitStatus
    func fetch(allowKeychainPrompt: Bool) async throws -> LimitStatus { status }
}
private struct WCCodex: CodexLimitsProviding {
    var status: CodexRateLimitStatus?
    func fetch() async throws -> CodexRateLimitStatus? { status }
}
private struct WCAntigravity: AntigravityLimitsProviding {
    func fetch(allowKeychainPrompt: Bool) async throws -> AntigravityRateLimitStatus {
        throw LimitsError.keychainInteractionNotAllowed
    }
}
private final class WCStatus: ProviderStatusProviding, @unchecked Sendable {
    func fetch() async -> [String: ProviderStatus] { [:] }
}
/// A local provider used today, so that its limits show.
private struct WCProvider: UsageProvider {
    let id: String
    let displayName: String
    func fetchDaily() async throws -> DailyUsage? {
        DailyUsage(date: LocalUsageReader.todayKey(), inputTokens: 0, outputTokens: 0, cacheCreationTokens: 0,
                   cacheReadTokens: 0, totalTokens: 1_000, totalCost: 0)
    }
    func fetchEnrichment() async -> ProviderEnrichment { ProviderEnrichment.local(entries: [], now: Date()) }
}

/// The limit windows pay their candies as they fill (`RareCandy.candiesDue`): a whole Pro session is one candy, a whole
/// Pro week five, and a bigger plan pays as many Pro plans as it holds, so every plan earns them at the same pace
/// whether or not it reaches its limit.
@MainActor
final class WindowCandyTests: XCTestCase {
    nonisolated(unsafe) private var defaults: UserDefaults!
    nonisolated(unsafe) private var suiteName: String!
    override func setUp() {
        super.setUp()
        suiteName = "wc-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func companion(_ edit: (inout CompanionState) -> Void = { _ in }) throws -> CompanionStore {
        var state = CompanionState()
        state.installBaselineSet = true
        edit(&state)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wc-\(UUID().uuidString).json")
        try JSONEncoder().encode(state).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let line = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []), rarity: .common, names: [:])
        return CompanionStore(provider: StubProvider(value: line), clock: { Date() }, fileURL: url, rng: SeededRNG(seed: 7))
    }

    func testWhatAWindowOwesFollowsItsPlan() {
        func due(_ utilization: Double, _ kind: WindowClass, _ plan: Int) -> Int {
            RareCandy.candiesDue(utilization: utilization, kind: kind, planMultiplier: plan)
        }
        // Pro: one candy for the whole session, five for the whole week, one every fifth of it.
        XCTAssertEqual(due(99, .session, 1), 0)
        XCTAssertEqual(due(100, .session, 1), 1)
        XCTAssertEqual(due(19, .weekly, 1), 0)
        XCTAssertEqual(due(20, .weekly, 1), 1)
        XCTAssertEqual(due(100, .weekly, 1), 5)
        // Max 5x: a fifth of its session is a whole Pro session.
        XCTAssertEqual(due(20, .session, 5), 1)
        XCTAssertEqual(due(59, .session, 5), 2)
        XCTAssertEqual(due(100, .session, 5), 5)
        XCTAssertEqual(due(4, .weekly, 5), 1)
        // Max 20x: every 5% of its session, every 1% of its week.
        XCTAssertEqual(due(5, .session, 20), 1)
        XCTAssertEqual(due(1, .weekly, 20), 1)
        XCTAssertEqual(due(100, .weekly, 20), 100)
        // Past the limit pays no more; nothing used pays nothing.
        XCTAssertEqual(due(130, .session, 5), 5)
        XCTAssertEqual(due(0, .weekly, 20), 0)
        XCTAssertEqual(due(.nan, .weekly, 20), 0)
        XCTAssertEqual(due(50, .session, 0), 0, "an unknown plan pays as a Pro plan")
    }

    /// The ledger pays only what is new; a new epoch starts it again, and a dip pays nothing twice.
    func testTheLedgerPaysWhatIsNewAndStartsAgainWithEachWindow() {
        var ledger: [String: Int] = [:], epochs: [String: String] = [:]
        func pay(_ utilization: Double, epoch: String? = "e1", plan: Int = 5) -> [CandyGrant] {
            CompanionStore.evaluateCandyGrants(
                windows: [CandyWindow(key: "w", name: "W", kind: .session, utilization: utilization, epoch: epoch,
                                      planMultiplier: plan)],
                grantTier: &ledger, windowEpoch: &epochs)
        }
        XCTAssertEqual(pay(10), [])
        XCTAssertEqual(pay(25).map(\.count), [1])
        XCTAssertEqual(pay(39), [])
        XCTAssertEqual(pay(41).map(\.count), [1])
        XCTAssertEqual(pay(38), [], "a dip pays nothing")
        XCTAssertEqual(pay(41), [], "and its return pays nothing twice")
        let full = pay(100)
        XCTAssertEqual(full.map(\.count), [3])
        XCTAssertEqual(full.first?.completesWindow, true)
        XCTAssertEqual(pay(30, epoch: "e2").map(\.count), [1], "a new window owes from its start")
        // Without an epoch, a window back to nothing owed is a new one.
        ledger = [:]; epochs = [:]
        XCTAssertEqual(pay(100, epoch: nil, plan: 1).map(\.count), [1])
        XCTAssertEqual(pay(100, epoch: nil, plan: 1), [])
        XCTAssertEqual(pay(3, epoch: nil, plan: 1), [])
        XCTAssertEqual(pay(100, epoch: nil, plan: 1).map(\.count), [1])
    }

    /// Each Claude account pays at its own plan; Codex, whose plans publish no ratio, as a Pro plan.
    func testEachAccountPaysAtItsPlan() async throws {
        let now = Date()
        let iso = ISO8601DateFormatter()
        var claude = try JSONDecoder().decode(LimitStatus.self, from: Data("""
        {"five_hour":{"utilization":25,"resets_at":"\(iso.string(from: now.addingTimeInterval(3600)))"},
         "seven_day":{"utilization":10,"resets_at":"\(iso.string(from: now.addingTimeInterval(2 * 86_400)))"}}
        """.utf8))
        claude.subscriptionType = "max"
        claude.rateLimitTier = "default_claude_max_20x"
        let codexReset = Int(now.addingTimeInterval(3600).timeIntervalSince1970)
        let codex = try JSONDecoder().decode(CodexRateLimitStatus.self, from: Data("""
        {"rateLimits":{"primary":{"usedPercent":100,"windowDurationMins":300,"resetsAt":\(codexReset)}}}
        """.utf8))
        let store = UsageStore(
            providers: [WCProvider(id: "claude_code", displayName: "Claude Code"), WCProvider(id: "codex", displayName: "Codex")],
            claudeLimitsProvider: WCClaude(status: claude), codexLimitsProvider: WCCodex(status: codex),
            antigravityLimitsProvider: WCAntigravity(), statusProvider: WCStatus(), autoRefresh: false, defaults: defaults)
        await store.refresh(scheduleEmptyRetry: false)
        let windows = Dictionary(uniqueKeysWithValues: store.candyEligibleWindows.map { ($0.key, $0) })
        XCTAssertEqual(windows["claude.fiveHour"]?.planMultiplier, 20)
        XCTAssertEqual(windows["claude.sevenDay"]?.planMultiplier, 20)
        XCTAssertEqual(windows["codex.codex.primary"]?.planMultiplier, 1)

        let s = try companion()
        s.grantCandies(from: [], limitsReady: true)
        s.grantCandiesFilling(store.candyEligibleWindows)
        XCTAssertEqual(s.rareCandyCount, 5 + 10 + 1, "a quarter of a Max 20x session, a tenth of its week, a full Codex session")
    }

    /// A window first seen after the first run, or seen at another plan, pays from then on, not what it used before
    /// all at once (#79): a Max 20x login added at 80% of its week paid 80 candies, a Pro week at 60% read as Max 5x 12.
    func testAWindowFirstSeenOrAtAnotherPlanPaysFromThen() throws {
        let s = try companion()
        s.grantCandies(from: [], limitsReady: true)
        let window = { (key: String, u: Double, plan: Int, epoch: String) in
            CandyWindow(key: key, name: key, kind: .weekly, utilization: u, epoch: epoch, planMultiplier: plan)
        }
        s.grantCandies(from: [window("max", 80, 20, "e")], limitsReady: true)
        XCTAssertEqual(s.rareCandyCount, 0, "first seen at 80%")
        s.grantCandies(from: [window("max", 83, 20, "e")], limitsReady: true)
        XCTAssertEqual(s.rareCandyCount, 3, "then one every 1%")

        s.grantCandiesFilling([window("pro", 60, 1, "e")])
        XCTAssertEqual(s.rareCandyCount, 6, "a Pro week at 60%")
        s.grantCandies(from: [window("pro", 60, 5, "e")], limitsReady: true)
        XCTAssertEqual(s.rareCandyCount, 6, "read as Max 5x: the jump pays nothing")
        s.grantCandies(from: [window("pro", 64, 5, "e")], limitsReady: true)
        XCTAssertEqual(s.rareCandyCount, 7, "then a Max 5x week's pace, one every 4%")
        s.grantCandies(from: [window("pro", 64, 1, "e")], limitsReady: true)
        XCTAssertEqual(s.rareCandyCount, 7, "read as 1 in the same window: the plan known stays, nothing paid twice")
        s.grantCandies(from: [window("pro", 20, 1, "e2")], limitsReady: true)
        XCTAssertEqual(s.rareCandyCount, 8, "a new epoch at the same plan pays from its start")
        XCTAssertEqual(s.state.candyWindowPlan, ["max": 20, "pro": 1])
    }

    /// [Regression] A plan read as 1 for one poll (unknown: the session key answers without it) while a bigger plan is
    /// known for the same window keeps the known one: re-seeded at 1 and back, the window lost what it owed between.
    func testAPlanReadAsOneForAPollLosesNothing() throws {
        let s = try companion()
        s.grantCandies(from: [], limitsReady: true)
        let end = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3 * 86_400))
        let window = { (u: Double, plan: Int) in
            CandyWindow(key: "max", name: "M", kind: .weekly, utilization: u, epoch: end, planMultiplier: plan)
        }
        s.grantCandies(from: [window(60, 5)], limitsReady: true)
        XCTAssertEqual(s.rareCandyCount, 0, "first seen at 60%")
        s.grantCandies(from: [window(64, 1)], limitsReady: true)
        XCTAssertEqual(s.rareCandyCount, 1, "read as 1: paid at the plan known, one every 4%")
        s.grantCandies(from: [window(68, 5)], limitsReady: true)
        XCTAssertEqual(s.rareCandyCount, 2, "back to 5: nothing lost in between")
        XCTAssertEqual(s.state.candyWindowPlan["max"], 5)
    }

    /// [Regression] A window whose stored one has ended starts from nothing even at another plan, or first seen at a
    /// plan: an old save opened after the reset carried last week's count over, and paid nothing until past it.
    func testANewWindowAtAnotherPlanDoesNotKeepTheEndedOnesCount() throws {
        let ended = Date().addingTimeInterval(-2 * 86_400)
        let iso = ISO8601DateFormatter()
        let s = try companion {
            $0.candyFeatureSeeded = true
            $0.candyGrantsAsYouGo = true
            $0.candyGrantTier = ["w": 20, "old": 4]
            $0.candyWindowEpoch = ["w": iso.string(from: ended), "old": iso.string(from: ended)]
            $0.candyWindowPlan = ["w": 5]
        }
        let next = iso.string(from: ended.addingTimeInterval(7 * 86_400))
        s.grantCandies(from: [
            CandyWindow(key: "w", name: "W", kind: .weekly, utilization: 10, epoch: next, planMultiplier: 20),
            CandyWindow(key: "old", name: "O", kind: .weekly, utilization: 40, epoch: next, planMultiplier: 1),
        ], limitsReady: true)
        XCTAssertEqual(s.rareCandyCount, 10 + 2, "a tenth of a Max 20x week, two fifths of a Pro one")
        XCTAssertEqual(s.state.candyWindowPlan, ["w": 20, "old": 1])
        XCTAssertEqual(s.state.candyWindowEpoch["w"], next)
    }

    func testThePlanOfALimitStatus() {
        var status = LimitStatus()
        XCTAssertEqual(status.planMultiplier, 1, "unknown")
        status.subscriptionType = "pro"
        status.rateLimitTier = "default_claude_pro"
        XCTAssertEqual(status.planMultiplier, 1)
        status.subscriptionType = "max"
        status.rateLimitTier = "default_claude_max_5x"
        XCTAssertEqual(status.planMultiplier, 5)
        status.rateLimitTier = "default_claude_max_20x"
        XCTAssertEqual(status.planMultiplier, 20)
        status.rateLimitTier = nil
        XCTAssertEqual(status.planMultiplier, 5, "a Max plan without its tier: the smallest Max")
    }

    /// A save from the rule that paid at 100% only: a window it already paid owes nothing more in its epoch, any
    /// other pays its usage so far, once.
    func testASaveFromTheRulePaidAtTheLimitOnlyPaysWhatItDidNot() throws {
        let s = try companion {
            $0.candyFeatureSeeded = true
            $0.candyGrantTier = ["paid": 1]
        }
        let windows = [
            CandyWindow(key: "paid", name: "P", kind: .weekly, utilization: 100, epoch: "e", planMultiplier: 1),
            CandyWindow(key: "open", name: "O", kind: .session, utilization: 60, epoch: "e", planMultiplier: 5),
        ]
        s.grantCandies(from: windows, limitsReady: true)
        XCTAssertEqual(s.rareCandyCount, 3, "three fifths of a Max 5x session; the week was paid at its limit")
        XCTAssertTrue(s.state.candyGrantsAsYouGo)
        s.grantCandies(from: windows, limitsReady: true)
        XCTAssertEqual(s.rareCandyCount, 3)
    }

    /// The first run pays nothing back: the windows pay from then on.
    func testTheFirstRunPaysNothingBack() throws {
        let s = try companion()
        let window = { (u: Double) in CandyWindow(key: "w", name: "W", kind: .weekly, utilization: u, epoch: "e", planMultiplier: 20) }
        s.grantCandies(from: [window(40)], limitsReady: true)
        XCTAssertEqual(s.rareCandyCount, 0)
        s.grantCandies(from: [window(43)], limitsReady: true)
        XCTAssertEqual(s.rareCandyCount, 3)
    }
}

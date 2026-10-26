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
/// A local provider whose entries are the given turns, through the shared enrichment.
private struct WCProvider: UsageProvider {
    let id: String
    let displayName: String
    let entries: [LocalUsageReader.Entry]
    func fetchDaily() async throws -> DailyUsage? {
        DailyUsage(date: LocalUsageReader.todayKey(), inputTokens: 0, outputTokens: 0, cacheCreationTokens: 0,
                   cacheReadTokens: 0, totalTokens: 1_000, totalCost: 0)
    }
    func fetchEnrichment() async -> ProviderEnrichment { ProviderEnrichment.local(entries: entries, now: Date()) }
}

/// A full limit window pays a tenth of the tokens it held in candies, at least one (#59): the same per token for every
/// plan, each window summed from its account's or provider's own turns since its start.
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

    private func turn(_ tokens: Int, hoursAgo: Double, now: Date = Date(), session: String? = nil) -> LocalUsageReader.Entry {
        let date = now.addingTimeInterval(-hoursAgo * 3600)
        var entry = LocalUsageReader.Entry(id: UUID().uuidString, date: date,
                                           localDay: LocalUsageReader.localDayFormatter().string(from: date),
                                           model: "claude-sonnet-4-5", input: 0, output: tokens, cacheWrite: 0, cacheRead: 0)
        entry.sessionID = session
        return entry
    }

    func testTheGrantIsATenthOfTheWindowsTokens() {
        XCTAssertEqual(RareCandy.grantCount(windowTokens: 5_000_000_000, kind: .weekly), 5, "5B pays the old weekly 5")
        XCTAssertEqual(RareCandy.grantCount(windowTokens: 23_000_000_000, kind: .weekly), 23)
        XCTAssertEqual(RareCandy.grantCount(windowTokens: 1_500_000_000, kind: .session), 2)
        XCTAssertEqual(RareCandy.grantCount(windowTokens: 300_000_000, kind: .weekly), 1, "never less than one")
        XCTAssertEqual(RareCandy.grantCount(windowTokens: 0, kind: .weekly), 1, "usage outside the local logs")
        XCTAssertEqual(RareCandy.grantCount(windowTokens: nil, kind: .weekly), RareCandy.weeklyGrant, "unknown: as before")
        XCTAssertEqual(RareCandy.grantCount(windowTokens: nil, kind: .session), 1)
    }

    /// The last week, minute by minute: a window sums what came from its start on.
    func testTheTimelineSumsFromAWindowsStart() {
        let now = Date()
        let timeline = TokenTimeline(entries: [turn(100, hoursAgo: 1, now: now), turn(20, hoursAgo: 1, now: now),
                                               turn(7, hoursAgo: 30, now: now), turn(9_999, hoursAgo: 24 * 8, now: now),
                                               turn(0, hoursAgo: 2, now: now)], now: now)
        XCTAssertEqual(timeline.tokens(since: now.addingTimeInterval(-5 * 3600)), 120)
        XCTAssertEqual(timeline.tokens(since: now.addingTimeInterval(-7 * 24 * 3600)), 127, "older than a week is gone")
        XCTAssertEqual(timeline.minuteStarts.count, 2, "one minute holds both turns")
        XCTAssertEqual(timeline.windowTokens(reset: now.addingTimeInterval(3600), span: LimitWindowSpan.fiveHour), 120)
        XCTAssertNil(timeline.windowTokens(reset: nil, span: LimitWindowSpan.fiveHour))
        XCTAssertNil(timeline.windowTokens(reset: now, span: nil))
    }

    /// Claude's 5h window counts its last turns, its weekly window the week's; Codex its own.
    func testEachFullWindowPaysItsOwnTokens() async throws {
        let now = Date()
        let iso = ISO8601DateFormatter()
        let fiveHourReset = iso.string(from: now.addingTimeInterval(3600))
        let weeklyReset = iso.string(from: now.addingTimeInterval(2 * 24 * 3600))
        let claude = try JSONDecoder().decode(LimitStatus.self, from: Data("""
        {"five_hour":{"utilization":100,"resets_at":"\(fiveHourReset)"},
         "seven_day":{"utilization":100,"resets_at":"\(weeklyReset)"}}
        """.utf8))
        let codexReset = Int(now.addingTimeInterval(3600).timeIntervalSince1970)
        let codex = try JSONDecoder().decode(CodexRateLimitStatus.self, from: Data("""
        {"rateLimits":{"primary":{"usedPercent":100,"windowDurationMins":300,"resetsAt":\(codexReset)}}}
        """.utf8))
        let store = UsageStore(
            providers: [
                WCProvider(id: "claude_code", displayName: "Claude Code",
                           entries: [turn(3_000_000_000, hoursAgo: 2), turn(20_000_000_000, hoursAgo: 72),
                                     turn(50_000_000_000, hoursAgo: 24 * 9)]),
                WCProvider(id: "codex", displayName: "Codex", entries: [turn(1_400_000_000, hoursAgo: 1)]),
            ],
            claudeLimitsProvider: WCClaude(status: claude), codexLimitsProvider: WCCodex(status: codex),
            antigravityLimitsProvider: WCAntigravity(), statusProvider: WCStatus(), autoRefresh: false, defaults: defaults)
        await store.refresh(scheduleEmptyRetry: false)
        let windows = Dictionary(uniqueKeysWithValues: store.candyEligibleWindows.map { ($0.key, $0) })
        XCTAssertEqual(windows["claude.fiveHour"]?.windowTokens, 3_000_000_000)
        XCTAssertEqual(windows["claude.sevenDay"]?.windowTokens, 23_000_000_000)
        XCTAssertEqual(windows["codex.codex.primary"]?.windowTokens, 1_400_000_000)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wc-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let line = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []), rarity: .common, names: [:])
        let companion = CompanionStore(provider: StubProvider(value: line), clock: { now }, fileURL: url, rng: SeededRNG(seed: 7))
        companion.grantCandies(from: [], limitsReady: true)
        companion.grantCandies(from: store.candyEligibleWindows, limitsReady: store.limitsReady)
        XCTAssertEqual(companion.rareCandyCount, 3 + 23 + 1, "3B, 23B and 1.4B")
    }

    /// With several Claude accounts, each one's week holds its own turns.
    func testEachClaudeAccountHasItsOwnWeek() {
        let now = Date()
        let promptTime = now.addingTimeInterval(-80 * 3600)
        let accounts = [ClaudeAccountUsageAttribution.Account(id: "work", prompts: ["w": [promptTime]]),
                        ClaudeAccountUsageAttribution.Account(id: "personal", prompts: ["p": [promptTime]])]
        let fmt = LocalUsageReader.localDayFormatter()
        let result = ClaudeAccountUsageAttribution.usage(
            entries: [turn(500, hoursAgo: 70, now: now, session: "w"), turn(40, hoursAgo: 1, now: now, session: "p"),
                      turn(3, hoursAgo: 60, now: now, session: "nobody")],
            accounts: accounts, now: now, todayKey: fmt.string(from: now),
            monthStartKey: fmt.string(from: LocalUsageReader.startOfMonth(now)))
        XCTAssertEqual(result.timelines["work"]?.tokens(since: now.addingTimeInterval(-TokenTimeline.span)), 500)
        XCTAssertEqual(result.timelines["personal"]?.tokens(since: now.addingTimeInterval(-TokenTimeline.span)), 40)
        XCTAssertEqual(Set(result.timelines.keys), ["work", "personal"], "unattributed turns count for no account")
        XCTAssertLessThanOrEqual(UsageStore.claudeUsageScanStart(now: now), now.addingTimeInterval(-TokenTimeline.span))
    }
}

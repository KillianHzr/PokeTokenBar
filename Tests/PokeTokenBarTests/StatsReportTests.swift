import XCTest
@testable import PokeTokenBar

// A fixed UTC calendar whose weeks start on Monday, so nothing depends on the machine running the suite.

private let utc = TimeZone(identifier: "UTC")!

private func calendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    calendar.firstWeekday = 2
    return calendar
}

private func date(_ month: Int, _ day: Int, hour: Int = 12) -> Date {
    calendar().date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
}

private func key(_ month: Int, _ day: Int) -> String {
    LocalUsageReader.localDayFormatter(timeZone: utc).string(from: date(month, day))
}

private func usage(_ day: String, _ tokens: Int, cost: Double = 0, coverage: CostCoverage = .source,
                   kinds: (input: Int, output: Int, write: Int, read: Int) = (0, 0, 0, 0)) -> DailyUsage {
    DailyUsage(date: day, inputTokens: kinds.input, outputTokens: kinds.output, cacheCreationTokens: kinds.write,
               cacheReadTokens: kinds.read, totalTokens: tokens, totalCost: cost, costCoverage: coverage)
}

/// A ledger recording since `since`, with usage on the given days.
private func ledger(since: String, _ days: [(String, Int)]) -> UsageLedger {
    var ledger = UsageLedger()
    ledger.merge([usage(since, 0)] + days.map { usage($0.0, $0.1) })
    return ledger
}

private func costs(_ days: [(String, Double)]) -> CostLedger {
    var ledger = CostLedger()
    ledger.merge(days.map { usage($0.0, 1, cost: $0.1) })
    return ledger
}

private func report(_ ledger: UsageLedger, _ scope: RecapScope, offset: Int = 0, now: Date = date(9, 18),
                    costs: CostLedger = CostLedger(), tools: [StatsReport.ToolSeries] = [],
                    dex: [DexEntry] = []) -> StatsReport {
    let calendar = calendar()
    let period = RecapPeriod(scope: scope, containing: now, calendar: calendar).shifted(by: offset, calendar: calendar)
    let recap = UsageRecap.make(ledger: ledger, dex: dex, period: period, now: now, calendar: calendar)
    return StatsReport.make(recap: recap, ledger: ledger, costs: costs, tools: tools, dex: dex, now: now,
                            calendar: calendar)
}

private func graduate(on day: Date, released: Bool = false) -> DexEntry {
    DexEntry(baseID: 10, finalID: 10, chainOrder: [10], rarity: .common, caughtAt: day,
             releasedAt: released ? day : nil)
}

// MARK: Cost ledger

final class CostLedgerTests: XCTestCase {
    func testOnlyAWhollyPricedDayIsRecordedAndNoneGoesDown() {
        var ledger = CostLedger()
        ledger.merge([
            usage("2026-09-10", 100, cost: 4),
            usage("2026-09-11", 100, cost: 0, coverage: .unavailable),
            usage("2026-09-12", 100, cost: 3, coverage: CostCoverage(reported: true, unknown: true)),
            usage("2026-09-13", 0, cost: 0),
        ])
        XCTAssertEqual(ledger.cost(on: "2026-09-10"), 4)
        XCTAssertNil(ledger.cost(on: "2026-09-11"), "no price")
        XCTAssertNil(ledger.cost(on: "2026-09-12"), "a partial price would price the day low")
        XCTAssertNil(ledger.cost(on: "2026-09-13"), "nothing used, nothing to price")

        ledger.merge([usage("2026-09-10", 100, cost: 2.5)])
        XCTAssertEqual(ledger.cost(on: "2026-09-10"), 4, "a rotated log must not lower a day")
        ledger.merge([usage("2026-09-10", 140, cost: 5, coverage: CostCoverage(reported: true, unknown: true))])
        XCTAssertNil(ledger.cost(on: "2026-09-10"), "a day that gains an unpriced part is no longer known")
    }

    /// [Regression] A read of a priced day with a part unpriced and no more tokens (a price list not loaded yet, one
    /// provider's read failing) is the same day read worse: it erased the day's cost, and the period showed none.
    func testAWorseReadOfAPricedDayKeepsItsCost() throws {
        var ledger = CostLedger()
        ledger.merge([usage("2026-09-10", 100, cost: 4)])
        ledger.merge([usage("2026-09-10", 100, cost: 1, coverage: CostCoverage(reported: true, unknown: true))])
        ledger.merge([usage("2026-09-10", 60, cost: 0, coverage: .unavailable)])
        XCTAssertEqual(ledger.cost(on: "2026-09-10"), 4)

        let defaults = try XCTUnwrap(UserDefaults(suiteName: "cost-ledger-tokens-\(UUID().uuidString)"))
        ledger.save(to: defaults)
        var reloaded = CostLedger.load(from: defaults)
        XCTAssertEqual(reloaded, ledger, "the priced tokens outlive a relaunch")
        reloaded.merge([usage("2026-09-10", 101, cost: 4, coverage: .unavailable)])
        XCTAssertNil(reloaded.cost(on: "2026-09-10"), "more tokens, unpriced: no longer known")
    }

    func testItSurvivesARelaunchWithoutJunkAndPrunesLikeTheTokens() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "cost-ledger-\(UUID().uuidString)"))
        var ledger = costs([("2026-01-02", 1.5), ("2026-09-10", 2)])
        ledger.save(to: defaults)
        XCTAssertEqual(CostLedger.load(from: defaults), ledger)

        var stored = defaults.dictionary(forKey: CostLedger.defaultsKey) ?? [:]
        stored["not a day"] = 3.0
        stored["2026-09-11"] = -1.0
        defaults.set(stored, forKey: CostLedger.defaultsKey)
        XCTAssertEqual(CostLedger.load(from: defaults), ledger, "hand-edited junk is dropped")

        ledger.prune(before: "2026-02-01")
        XCTAssertNil(ledger.cost(on: "2026-01-02"))
        XCTAssertEqual(ledger.cost(on: "2026-09-10"), 2)
    }
}

// MARK: The period

final class StatsReportTests: XCTestCase {
    func testThePeriodCostsItsPricedDaysAndNothingWhenOneIsNot() {
        let tokens = ledger(since: key(9, 1), [(key(9, 14), 100), (key(9, 15), 200), (key(9, 17), 300)])
        let priced = costs([(key(9, 14), 1), (key(9, 15), 2), (key(9, 17), 3)])
        XCTAssertEqual(report(tokens, .week, costs: priced).cost, 6)
        XCTAssertNil(report(tokens, .week, costs: costs([(key(9, 14), 1), (key(9, 17), 3)])).cost,
                     "the 15th used tokens nobody priced")
        XCTAssertNil(report(ledger(since: key(9, 1), []), .week, costs: priced).cost, "an idle week has no bill")
    }

    /// Friday the 18th: Monday to Thursday against Monday to Thursday of the week before, today in neither.
    func testARunningPeriodComparesItsCompletedDaysOnly() throws {
        let days = [(key(9, 7), 100), (key(9, 8), 100), (key(9, 9), 100), (key(9, 10), 100), (key(9, 11), 900),
                    (key(9, 14), 150), (key(9, 15), 150), (key(9, 16), 150), (key(9, 17), 150)]
        let change = try XCTUnwrap(report(ledger(since: key(9, 1), days), .week).change)
        XCTAssertEqual(change, 0.5, accuracy: 0.0001, "600 against 400; last Friday's 900 is not compared")
        let withToday = try XCTUnwrap(report(ledger(since: key(9, 1), days + [(key(9, 18), 5_000)]), .week).change)
        XCTAssertEqual(withToday, 0.5, accuracy: 0.0001, "half of today never counts against a whole day")
    }

    func testOneCompletedDayIsNotEnoughToCompare() {
        let days = [(key(9, 7), 100), (key(9, 8), 100), (key(9, 15), 0), (key(9, 16), 50)]
        let tokens = ledger(since: key(9, 1), days)
        XCTAssertNil(report(tokens, .week, now: date(9, 15)).change, "Tuesday: Monday alone would read as -100%")
        XCTAssertNotNil(report(tokens, .week, now: date(9, 16)).change, "Wednesday: two days")
    }

    func testAFinishedPeriodComparesWithTheWholePeriodBefore() throws {
        let days = [(key(8, 31), 100), (key(9, 6), 300), (key(9, 7), 200), (key(9, 13), 600)]
        let change = try XCTUnwrap(report(ledger(since: key(8, 31), days), .week, offset: -1).change)
        XCTAssertEqual(change, 1, accuracy: 0.0001, "800 against 400")
        XCTAssertNil(report(ledger(since: key(9, 7), days.filter { $0.0 >= key(9, 7) }), .week, offset: -1).change,
                     "the ledger does not reach the week before")
    }

    /// The 31st of March: 30 completed days against February's 28, so 28 on both sides; the same 100 a day is no change.
    func testARunningMonthComparesAsManyDaysOnBothSides() throws {
        let days = (1...28).map { (key(2, $0), 100) } + (1...30).map { (key(3, $0), 100) }
        let change = try XCTUnwrap(report(ledger(since: key(2, 1), days), .month, now: date(3, 31)).change)
        XCTAssertEqual(change, 0, accuracy: 0.0001, "not +7%: 3,000 against 2,800")
    }

    /// The 18th of September: 17 completed days at 100 a day, 12 days left after today.
    func testAProjectionGoesOnAtTheCompletedDaysPace() throws {
        let completed = (1...17).map { (key(9, $0), 100) }
        let priced = costs((1...18).map { (key(9, $0), $0 == 18 ? 0.3 : 1) })
        let slow = try XCTUnwrap(report(ledger(since: key(9, 1), completed + [(key(9, 18), 30)]), .month,
                                        costs: priced).projection)
        XCTAssertEqual(slow.tokens, 1_700 + 100 + 12 * 100, "a quiet morning still counts as an average day")
        XCTAssertEqual(try XCTUnwrap(slow.cost), 17 + 1 + 12, accuracy: 0.0001)
        let busy = try XCTUnwrap(report(ledger(since: key(9, 1), completed + [(key(9, 18), 250)]), .month).projection)
        XCTAssertEqual(busy.tokens, 1_700 + 250 + 12 * 100, "a busy today is already more than the average")
        XCTAssertNil(busy.cost, "nothing priced, no projected cost")
    }

    func testNoProjectionOnceOverOrWithoutTheStart() {
        let days = (1...17).map { (key(9, $0), 100) }
        XCTAssertNil(report(ledger(since: key(8, 1), days), .month, offset: -1).projection, "August is over")
        XCTAssertNil(report(ledger(since: key(9, 10), days.filter { $0.0 >= key(9, 10) }), .month).projection,
                     "the 1st to the 9th were not recorded: their pace is unknown")
        XCTAssertNil(report(ledger(since: key(9, 1), days), .week, now: date(9, 15)).projection,
                     "one completed day is no pace")
    }

    func testTheSplitNeedsEveryActiveDayInTheMonthSeries() throws {
        let month = (1...18).map { key(9, $0) }
        let claude = StatsReport.ToolSeries(id: "claude_code", name: "Claude Code", days: month.map {
            usage($0, $0 == key(9, 15) ? 1_000 : 0, cost: 2, kinds: $0 == key(9, 15) ? (20, 10, 70, 900) : (0, 0, 0, 0))
        }, reportsCost: true)
        let codex = StatsReport.ToolSeries(id: "codex", name: "Codex", days: month.map {
            usage($0, $0 == key(9, 16) ? 400 : 0, cost: 1, coverage: $0 == key(9, 16) ? .unavailable : .source)
        }, reportsCost: true)
        let local = StatsReport.ToolSeries(id: "local", name: "Local", days: month.map {
            usage($0, $0 == key(9, 16) ? 100 : 0)
        }, reportsCost: false)
        let tokens = ledger(since: key(8, 31), [(key(8, 31), 50), (key(9, 15), 1_000), (key(9, 16), 500)])

        let split = try XCTUnwrap(report(tokens, .week, tools: [local, codex, claude]).breakdown)
        XCTAssertEqual([split.input, split.output, split.cacheWrite, split.cacheRead], [20, 10, 70, 900])
        XCTAssertEqual(split.unsplit, 500, "Codex and Local report no kinds")
        XCTAssertEqual(split.total, 1_500)
        XCTAssertEqual(split.tools.map(\.id), ["claude_code", "codex", "local"], "largest first")
        XCTAssertEqual(split.tools.map(\.cost), [2, nil, nil], "an unpriced day, a tool that prices nothing")

        XCTAssertNil(report(tokens, .week, offset: -2, tools: [local, codex, claude]).breakdown,
                     "31 August used tokens and is no longer in any series")
    }

    func testABarHoldsItsGraduatesCostAndToolsAndLeavesOutPokemonSentOff() throws {
        let month = (1...18).map { key(9, $0) }
        func tool(_ id: String, _ tokens: Int) -> StatsReport.ToolSeries {
            StatsReport.ToolSeries(id: id, name: id, days: month.map { usage($0, $0 == key(9, 15) ? tokens : 0) },
                                   reportsCost: true)
        }
        let tokens = ledger(since: key(9, 1), [(key(9, 15), 300)])
        let dex = [graduate(on: date(9, 15, hour: 9)), graduate(on: date(9, 15, hour: 20), released: true),
                   graduate(on: date(9, 16))]
        let stacked = report(tokens, .week, costs: costs([(key(9, 15), 4)]), tools: [tool("a", 200), tool("b", 100)],
                             dex: dex)
        let bar = try XCTUnwrap(stacked.recap.buckets.first { $0.key == key(9, 15) })
        let detail = stacked.detail(bar)
        XCTAssertEqual(detail.graduated, 1, "the one sent off for an egg never graduated")
        XCTAssertEqual(detail.cost, 4)
        XCTAssertEqual(detail.tools.map(\.tokens), [200, 100])
        XCTAssertTrue(stacked.stacksByTool)
        XCTAssertEqual(stacked.graduated.count, 2)

        let single = report(tokens, .week, tools: [tool("a", 300)], dex: dex)
        XCTAssertFalse(single.stacksByTool, "one tool draws plain bars")
    }
}

// MARK: Records

final class StatsRecordsTests: XCTestCase {
    private func records(_ ledger: UsageLedger, now: Date = date(9, 18)) -> StatsRecords {
        StatsRecords.make(ledger: ledger, now: now, calendar: calendar())
    }

    func testTheBestDayWeekAndMonth() {
        let made = records(ledger(since: key(7, 1), [(key(7, 2), 500), (key(7, 3), 500), (key(8, 4), 900),
                                                    (key(8, 25), 300), (key(8, 26), 300), (key(8, 27), 300)]))
        XCTAssertEqual(made.bestDay, StatsRecords.Record(key: key(8, 4), tokens: 900))
        XCTAssertEqual(made.bestWeek, StatsRecords.Record(key: key(6, 29), tokens: 1_000),
                       "two days of 500 beat one of 900: the week of Monday 29 June")
        XCTAssertEqual(made.bestMonth, StatsRecords.Record(key: key(8, 1), tokens: 1_800))
    }

    func testTheStreakRunsToTodayOrToYesterdayWhileTodayIsEmpty() {
        let days = [(key(9, 10), 1), (key(9, 11), 1), (key(9, 12), 1), (key(9, 13), 1), (key(9, 15), 1),
                    (key(9, 16), 1), (key(9, 17), 1)]
        let before = records(ledger(since: key(9, 1), days))
        XCTAssertEqual(before.longestStreak, 4)
        XCTAssertEqual(before.currentStreak, 3, "nothing yet today: the run up to yesterday still holds")
        let after = records(ledger(since: key(9, 1), days + [(key(9, 18), 1)]))
        XCTAssertEqual(after.currentStreak, 4)
        XCTAssertEqual(records(ledger(since: key(9, 1), [(key(9, 10), 1)])).currentStreak, 0)
    }

    /// Monday the 31st of August to Sunday the 13th of September: two of each weekday, Mondays at 100 and 300.
    func testTheUsualWeekNeedsTwoWeeksAndStartsOnTheFirstWeekday() throws {
        let days = [(key(8, 31), 100), (key(9, 1), 50), (key(9, 7), 300), (key(9, 13), 40)]
        XCTAssertNil(records(ledger(since: key(8, 31), days), now: date(9, 13)).weekdayAverages,
                     "13 days before today")
        let averages = try XCTUnwrap(records(ledger(since: key(8, 31), days + [(key(9, 14), 9_999)]),
                                             now: date(9, 14)).weekdayAverages)
        XCTAssertEqual(averages, [200, 25, 0, 0, 0, 0, 20], "Monday first, today left out")
    }
}

// MARK: Kept records

final class KeptRecordsTests: XCTestCase {
    func testKeptRecordsHoldTheBestOfEachAndSurviveAReload() throws {
        var kept = StatsRecords.Kept()
        kept.merge(StatsRecords(bestDay: .init(key: "2025-06-03", tokens: 40), bestWeek: nil, bestMonth: nil,
                                longestStreak: 60, currentStreak: 2, weekdayAverages: nil))
        kept.merge(StatsRecords(bestDay: .init(key: "2026-09-01", tokens: 30), bestWeek: .init(key: "2026-08-31", tokens: 90),
                                bestMonth: nil, longestStreak: 12, currentStreak: 3, weekdayAverages: nil))
        XCTAssertEqual(kept.bestDay, .init(key: "2025-06-03", tokens: 40))
        XCTAssertEqual(kept.bestWeek, .init(key: "2026-08-31", tokens: 90))
        XCTAssertEqual(kept.longestStreak, 60)
        let shown = StatsRecords(bestDay: .init(key: "2026-09-01", tokens: 30), bestWeek: nil, bestMonth: nil,
                                 longestStreak: 12, currentStreak: 3, weekdayAverages: [1, 2, 3, 4, 5, 6, 7]).keeping(kept)
        XCTAssertEqual(shown.bestDay?.tokens, 40, "the pruned day still the best")
        XCTAssertEqual(shown.currentStreak, 3, "the running streak is the ledger's")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "kept-records-\(UUID().uuidString)"))
        kept.save(to: defaults)
        XCTAssertEqual(StatsRecords.Kept.load(from: defaults), kept)
    }
}

// MARK: Recording

private enum StatsStubError: Error { case unavailable }
private struct StatsNoClaudeLimits: ClaudeLimitsProviding {
    func fetch(allowKeychainPrompt: Bool) async throws -> LimitStatus { throw StatsStubError.unavailable }
}
private struct StatsNoCodexLimits: CodexLimitsProviding {
    func fetch() async throws -> CodexRateLimitStatus? { nil }
}
private struct StatsNoAntigravityLimits: AntigravityLimitsProviding {
    func fetch(allowKeychainPrompt: Bool) async throws -> AntigravityRateLimitStatus { throw StatsStubError.unavailable }
}
private struct StatsNoStatus: ProviderStatusProviding {
    func fetch() async -> [String: ProviderStatus] { [:] }
}
private final class PricedProvider: UsageProvider, @unchecked Sendable {
    let id = "claude_code"
    let displayName = "Claude Code"
    let reportsCost = true
    private let series: [DailyUsage]
    init(series: [DailyUsage]) { self.series = series }
    func fetchDaily() async throws -> DailyUsage? { series.last }
    func fetchEnrichment() async -> ProviderEnrichment {
        var enrichment = ProviderEnrichment()
        enrichment.periodsOK = true
        enrichment.monthDaily = series
        return enrichment
    }
}

@MainActor
final class CostLedgerRecordingTests: XCTestCase {
    func testARefreshPricesTheDaysAndTheyOutliveARelaunch() async throws {
        let formatter = LocalUsageReader.localDayFormatter()
        let today = formatter.string(from: Date())
        let yesterday = formatter.string(from: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "cost-ledger-refresh-\(UUID().uuidString)"))
        let store = UsageStore(
            providers: [PricedProvider(series: [usage(yesterday, 900, cost: 7.5), usage(today, 300, cost: 2)])],
            claudeLimitsProvider: StatsNoClaudeLimits(), codexLimitsProvider: StatsNoCodexLimits(),
            antigravityLimitsProvider: StatsNoAntigravityLimits(), statusProvider: StatsNoStatus(),
            autoRefresh: false, defaults: defaults)

        await store.refresh(scheduleEmptyRetry: false)

        XCTAssertEqual(store.dailyCostLedger.cost(on: yesterday), 7.5)
        XCTAssertEqual(store.dailyCostLedger.cost(on: today), 2)
        XCTAssertEqual(CostLedger.load(from: defaults), store.dailyCostLedger)
    }

    /// The ledger keeps this year and the last: a best day before that leaves the ledger and stays the record.
    func testARecordOutlivesTheLedgersPruning() async throws {
        let calendar = RecapPeriod.calendar()
        let formatter = LocalUsageReader.localDayFormatter()
        let thisYear = RecapPeriod(scope: .year, containing: Date(), calendar: calendar)
        let twoYearsAgo = formatter.string(from: thisYear.shifted(by: -1, calendar: calendar).start.addingTimeInterval(-12 * 3600))
        let today = formatter.string(from: Date())
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "kept-records-refresh-\(UUID().uuidString)"))
        var seeded = UsageLedger()
        seeded.merge([usage(twoYearsAgo, 9_000)])
        seeded.save(to: defaults)
        let store = UsageStore(
            providers: [PricedProvider(series: [usage(today, 300, cost: 2)])],
            claudeLimitsProvider: StatsNoClaudeLimits(), codexLimitsProvider: StatsNoCodexLimits(),
            antigravityLimitsProvider: StatsNoAntigravityLimits(), statusProvider: StatsNoStatus(),
            autoRefresh: false, defaults: defaults)

        await store.refresh(scheduleEmptyRetry: false)

        XCTAssertEqual(store.dailyLedger.tokens(on: twoYearsAgo), 0, "pruned")
        XCTAssertEqual(store.keptRecords.bestDay, StatsRecords.Record(key: twoYearsAgo, tokens: 9_000))
        XCTAssertEqual(StatsRecords.Kept.load(from: defaults), store.keptRecords)
    }
}

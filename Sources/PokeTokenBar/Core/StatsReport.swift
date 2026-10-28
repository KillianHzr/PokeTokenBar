import Foundation

/// The cost of each past day, kept across months beside `UsageLedger`: providers price the current month only, so
/// without it the Stats page could not price last month or the year.
struct CostLedger: Equatable, Sendable {
    static let defaultsKey = "dailyCostLedger"

    private(set) var costByDay: [String: Double] = [:]

    func cost(on day: String) -> Double? { costByDay[day] }

    /// Records the days whose whole cost is known, and never lowers one, like the token ledger. A day with an unpriced
    /// part is dropped rather than priced low: a period over it shows no cost.
    mutating func merge(_ series: [DailyUsage]) {
        for day in series where day.totalTokens > 0 {
            if day.costCoverage.unknown || !day.costCoverage.hasKnown {
                costByDay[day.date] = nil
            } else {
                costByDay[day.date] = max(costByDay[day.date] ?? 0, day.totalCost)
            }
        }
    }

    mutating func prune(before cutoff: String) {
        costByDay = costByDay.filter { $0.key >= cutoff }
    }

    static func load(from defaults: UserDefaults) -> CostLedger {
        var ledger = CostLedger()
        // Hand-edited defaults are data, not truth: keep what parses as a day and a price.
        let formatter = LocalUsageReader.localDayFormatter()
        if let stored = defaults.dictionary(forKey: defaultsKey) as? [String: Double] {
            ledger.costByDay = stored.filter { formatter.date(from: $0.key) != nil && $0.value.isFinite && $0.value >= 0 }
        }
        return ledger
    }

    func save(to defaults: UserDefaults) {
        defaults.set(costByDay, forKey: Self.defaultsKey)
    }
}

/// What the Stats page tells of one week, month or year beyond `UsageRecap`: what it cost, how it compares with the
/// period before, where it is heading, where its tokens went and who graduated in it.
struct StatsReport {
    /// One tool's month, as its provider reports it.
    struct ToolSeries {
        let id: String
        let name: String
        let days: [DailyUsage]
        let reportsCost: Bool
    }

    struct Tool: Equatable {
        let id: String
        let name: String
        let tokens: Int
        /// nil when the tool prices nothing, or not all of these days.
        let cost: Double?
    }

    /// The period's tokens by kind and by tool.
    struct Breakdown: Equatable {
        let input: Int
        let output: Int
        let cacheWrite: Int
        let cacheRead: Int
        /// Tokens a tool reports without saying of which kind.
        let unsplit: Int
        /// Largest first, tools that used nothing left out.
        let tools: [Tool]
        var total: Int { input + output + cacheWrite + cacheRead + unsplit }
    }

    struct Projection: Equatable {
        let tokens: Int
        let cost: Double?
    }

    /// One bar of the chart: a day, or a month in the year view.
    struct BucketDetail: Equatable {
        let tokens: Int
        let cost: Double?
        let graduated: Int
        /// Empty unless every day of it is split by tool.
        let tools: [Tool]
    }

    let recap: UsageRecap
    /// The period's cost, when every day it used tokens on is priced.
    let cost: Double?
    /// Against the period before: the whole of it once over, the same completed days while running (today is left
    /// out of both, half a day against a whole one would read as a drop), from two of them. nil when the ledger does
    /// not reach both starts, or there is nothing to compare with.
    let change: Double?
    /// Where a running period ends at the pace of its completed days.
    let projection: Projection?
    /// nil unless every day with usage is still in the providers' month series.
    let breakdown: Breakdown?
    /// Pokémon graduated in the period, newest first. One sent off for an egg never graduated.
    let graduated: [DexEntry]

    private let details: [String: BucketDetail]

    func detail(_ bucket: UsageRecap.Bucket) -> BucketDetail {
        details[bucket.key] ?? BucketDetail(tokens: bucket.tokens, cost: nil, graduated: 0, tools: [])
    }

    /// The chart stacks its bars by tool only when two or more tools share the period and every day is split.
    var stacksByTool: Bool { (breakdown?.tools.count ?? 0) > 1 }

    static func make(recap: UsageRecap, ledger: UsageLedger, costs: CostLedger, tools: [ToolSeries],
                     dex: [DexEntry], now: Date, calendar: Calendar) -> StatsReport {
        let formatter = LocalUsageReader.localDayFormatter(timeZone: calendar.timeZone)
        let today = calendar.startOfDay(for: now)
        let todayKey = formatter.string(from: today)
        let period = recap.period

        /// The days from `start` to `end`, today at the latest: the future has no usage.
        func days(_ start: Date, _ end: Date) -> [String] {
            var result: [String] = []
            var cursor = calendar.startOfDay(for: start)
            while cursor < end, cursor <= today {
                result.append(formatter.string(from: cursor))
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
            return result
        }
        func known(_ key: String) -> Bool { ledger.tokens(on: key) > 0 || ledger.covers(key) }
        func tokens(_ keys: [String]) -> Int { keys.reduce(0) { $0 + ledger.tokens(on: $1) } }
        /// The cost of these days, nil as soon as one with usage is not priced.
        func cost(_ keys: [String]) -> Double? {
            var total = 0.0
            for key in keys where ledger.tokens(on: key) > 0 {
                guard let day = costs.cost(on: key) else { return nil }
                total += day
            }
            return total
        }

        let elapsed = days(period.start, period.end)
        let active = elapsed.filter { ledger.tokens(on: $0) > 0 }
        let completed = recap.isInProgress ? elapsed.filter { $0 != todayKey } : elapsed

        // The previous period, over as many days as this one has completed while it runs.
        let previous = period.shifted(by: -1, calendar: calendar)
        let previousDays = days(previous.start, previous.end)
        // While it runs, as many days on both sides: from the 29th, March has completed more days than February has.
        let sameDays = min(completed.count, previousDays.count)
        let current = recap.isInProgress ? Array(completed.prefix(sameDays)) : completed
        let compared = recap.isInProgress ? Array(previousDays.prefix(sameDays)) : previousDays
        let previousTotal = tokens(compared)
        // One completed day says little: a Monday off would read as a 100% drop.
        let change: Double? = if current.count >= (recap.isInProgress ? 2 : 1), let first = current.first,
                                 let previousFirst = compared.first, known(first), ledger.covers(previousFirst),
                                 previousTotal > 0 {
            Double(tokens(current) - previousTotal) / Double(previousTotal)
        } else {
            nil
        }

        // Linear: the completed days' average for the rest of today and every day left.
        var projection: Projection?
        if recap.isInProgress, completed.count >= 2, let first = completed.first, known(first) {
            var left = 0
            var day = calendar.date(byAdding: .day, value: 1, to: today) ?? period.end
            while day < period.end {
                left += 1
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
            if left > 0 {
                let average = Double(tokens(completed)) / Double(completed.count)
                let todayTokens = Double(ledger.tokens(on: todayKey))
                let projected = Double(tokens(completed)) + max(todayTokens, average) + average * Double(left)
                var projectedCost: Double?
                if let paid = cost(completed), let todayCost = cost([todayKey]) {
                    let averageCost = paid / Double(completed.count)
                    projectedCost = paid + max(todayCost, averageCost) + averageCost * Double(left)
                }
                projection = Projection(tokens: Int(projected.rounded()), cost: projectedCost)
            }
        }

        // Where the tokens went: only from days the providers still split, all of them or none.
        let seriesDays = Set(tools.flatMap { $0.days.map(\.date) })
        func toolSplit(_ keys: [String]) -> [Tool] {
            let wanted = Set(keys)
            return tools.compactMap { tool -> Tool? in
                let days = tool.days.filter { wanted.contains($0.date) && $0.totalTokens > 0 }
                let used = days.reduce(0) { $0 + $1.totalTokens }
                guard used > 0 else { return nil }
                let priced = tool.reportsCost && days.allSatisfy { $0.costCoverage.hasKnown && !$0.costCoverage.unknown }
                return Tool(id: tool.id, name: tool.name, tokens: used,
                            cost: priced ? days.reduce(0) { $0 + $1.totalCost } : nil)
            }
            .sorted { $0.tokens != $1.tokens ? $0.tokens > $1.tokens : $0.id < $1.id }
        }
        var breakdown: Breakdown?
        if !active.isEmpty, active.allSatisfy(seriesDays.contains) {
            let wanted = Set(active)
            let days = tools.flatMap(\.days).filter { wanted.contains($0.date) }
            let input = days.reduce(0) { $0 + $1.inputTokens }
            let output = days.reduce(0) { $0 + $1.outputTokens }
            let cacheWrite = days.reduce(0) { $0 + $1.cacheCreationTokens }
            let cacheRead = days.reduce(0) { $0 + $1.cacheReadTokens }
            let total = days.reduce(0) { $0 + $1.totalTokens }
            let split = toolSplit(active)
            if total > 0 {
                breakdown = Breakdown(input: input, output: output, cacheWrite: cacheWrite, cacheRead: cacheRead,
                                      unsplit: max(0, total - input - output - cacheWrite - cacheRead), tools: split)
            }
        }

        // A Pokémon sent off for an egg is in the Pokédex too, as an entry released before it graduated: not counted.
        let graduated = dex
            .filter { entry in !entry.isReleased && entry.caughtAt.map { $0 >= period.start && $0 < period.end } == true }
            .sorted { ($0.caughtAt ?? .distantPast) > ($1.caughtAt ?? .distantPast) }

        var details: [String: BucketDetail] = [:]
        for bucket in recap.buckets where bucket.hasData {
            let start = formatter.date(from: bucket.key) ?? period.start
            let end = period.scope == .year
                ? (calendar.date(byAdding: .month, value: 1, to: start) ?? period.end)
                : (calendar.date(byAdding: .day, value: 1, to: start) ?? period.end)
            let keys = days(start, end)
            let used = keys.filter { ledger.tokens(on: $0) > 0 }
            let count = graduated.filter { entry in entry.caughtAt.map { $0 >= start && $0 < end } == true }.count
            details[bucket.key] = BucketDetail(
                tokens: bucket.tokens, cost: used.isEmpty ? nil : cost(keys), graduated: count,
                tools: breakdown != nil && used.allSatisfy(seriesDays.contains) ? toolSplit(used) : [])
        }

        return StatsReport(recap: recap, cost: active.isEmpty ? nil : cost(active), change: change,
                           projection: projection, breakdown: breakdown, graduated: graduated, details: details)
    }
}

/// The records of every day the ledger holds (this year and the last; `Kept` holds older ones), and the usual week.
struct StatsRecords: Equatable {
    struct Record: Equatable, Codable {
        /// `yyyy-MM-dd` of the day, or of the first day of the week or month.
        let key: String
        let tokens: Int
    }

    let bestDay: Record?
    let bestWeek: Record?
    let bestMonth: Record?
    let longestStreak: Int
    /// Days in a row up to today, or up to yesterday while today has no usage yet.
    let currentStreak: Int
    /// Average tokens of each weekday from the calendar's first one, over the covered days before today. nil under
    /// two weeks of them: one Monday is not a habit.
    let weekdayAverages: [Int]?

    static func make(ledger: UsageLedger, now: Date, calendar: Calendar) -> StatsRecords {
        let formatter = LocalUsageReader.localDayFormatter(timeZone: calendar.timeZone)
        let today = calendar.startOfDay(for: now)
        let todayKey = formatter.string(from: today)
        let firstKey = ([ledger.coveredSince].compactMap { $0 } + ledger.tokensByDay.keys).min()
        guard let firstKey, let start = formatter.date(from: firstKey), start <= today else {
            return StatsRecords(bestDay: nil, bestWeek: nil, bestMonth: nil, longestStreak: 0, currentStreak: 0,
                                weekdayAverages: nil)
        }

        var dates: [Date] = []
        var cursor = calendar.startOfDay(for: start)
        while cursor <= today {
            dates.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        var weeks: [String: Int] = [:]
        var months: [String: Int] = [:]
        var bestDay: Record?
        var longest = 0
        var run = 0
        var sums = Array(repeating: 0, count: 7)
        var counts = Array(repeating: 0, count: 7)
        for date in dates {
            let key = formatter.string(from: date)
            let tokens = ledger.tokens(on: key)
            run = tokens > 0 ? run + 1 : 0
            longest = max(longest, run)
            guard tokens > 0 || ledger.covers(key) else { continue }
            if tokens > 0 {
                if tokens > (bestDay?.tokens ?? 0) { bestDay = Record(key: key, tokens: tokens) }
                let week = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
                weeks[formatter.string(from: week), default: 0] += tokens
                let month = calendar.dateInterval(of: .month, for: date)?.start ?? date
                months[formatter.string(from: month), default: 0] += tokens
            }
            if key != todayKey {
                let slot = (calendar.component(.weekday, from: date) - calendar.firstWeekday + 7) % 7
                sums[slot] += tokens
                counts[slot] += 1
            }
        }

        var current = 0
        var day = ledger.tokens(on: todayKey) > 0 ? today : calendar.date(byAdding: .day, value: -1, to: today)
        while let date = day, date >= start, ledger.tokens(on: formatter.string(from: date)) > 0 {
            current += 1
            day = calendar.date(byAdding: .day, value: -1, to: date)
        }

        func best(_ totals: [String: Int]) -> Record? {
            totals.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }
                .map { Record(key: $0.key, tokens: $0.value) }
        }
        return StatsRecords(
            bestDay: bestDay, bestWeek: best(weeks), bestMonth: best(months), longestStreak: longest,
            currentStreak: current,
            weekdayAverages: counts.reduce(0, +) >= 14 && !counts.contains(0)
                ? zip(sums, counts).map { $0 / $1 } : nil)
    }
}

extension StatsRecords {
    /// The records kept past the ledger's pruning, which keeps this year and the last: a best day of two years ago
    /// stays the best.
    struct Kept: Codable, Equatable {
        static let defaultsKey = "usageRecords"

        var bestDay: Record?
        var bestWeek: Record?
        var bestMonth: Record?
        var longestStreak = 0

        var isEmpty: Bool { bestDay == nil && longestStreak == 0 }

        mutating func merge(_ records: StatsRecords) {
            func best(_ a: Record?, _ b: Record?) -> Record? {
                guard let a else { return b }
                guard let b else { return a }
                return b.tokens > a.tokens ? b : a
            }
            bestDay = best(bestDay, records.bestDay)
            bestWeek = best(bestWeek, records.bestWeek)
            bestMonth = best(bestMonth, records.bestMonth)
            longestStreak = max(longestStreak, records.longestStreak)
        }

        static func load(from defaults: UserDefaults) -> Kept {
            defaults.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode(Kept.self, from: $0) } ?? Kept()
        }

        func save(to defaults: UserDefaults) {
            defaults.set(try? JSONEncoder().encode(self), forKey: Self.defaultsKey)
        }
    }

    /// These records with the kept ones, the best of both. The streak running now and the usual week stay the ledger's.
    func keeping(_ kept: Kept) -> StatsRecords {
        var merged = kept
        merged.merge(self)
        return StatsRecords(bestDay: merged.bestDay, bestWeek: merged.bestWeek, bestMonth: merged.bestMonth,
                            longestStreak: merged.longestStreak, currentStreak: currentStreak,
                            weekdayAverages: weekdayAverages)
    }
}

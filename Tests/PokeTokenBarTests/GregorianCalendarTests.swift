import XCTest
@testable import PokeTokenBar

/// Months, weeks and years are Gregorian whatever the system calendar: the day and month keys ("yyyy-MM-dd", "yyyy-MM")
/// are, and a Persian month started on the 22nd or 23rd, so the month's totals mixed two months and the event eggs fell
/// on Persian dates.
final class GregorianCalendarTests: XCTestCase {
    func testTheSharedCalendarIsGregorianInTheLocalZone() {
        let calendar = LocalUsageReader.gregorianCalendar()
        XCTAssertEqual(calendar.identifier, .gregorian)
        XCTAssertEqual(calendar.timeZone, .current)
        XCTAssertEqual(calendar.firstWeekday, Calendar.current.firstWeekday)
        let zone = TimeZone(identifier: "Asia/Tehran")!
        let mid = DateComponents(calendar: LocalUsageReader.gregorianCalendar(timeZone: zone),
                                 year: 2026, month: 10, day: 29, hour: 12).date!
        XCTAssertEqual(LocalUsageReader.startOfMonth(mid, calendar: LocalUsageReader.gregorianCalendar(timeZone: zone)),
                       DateComponents(calendar: LocalUsageReader.gregorianCalendar(timeZone: zone),
                                      year: 2026, month: 10, day: 1).date)
    }

    /// [Regression] `Calendar.current` follows the system calendar: only what is the same in every calendar (the start
    /// of a day, today, the first weekday, the weekday) may read it. A month, a week or a year reads the Gregorian one.
    func testOnlyDayLevelCodeReadsTheSystemCalendar() throws {
        // And the years a save kept in it, read back in it once (`CompanionState.convertCalendarYears`).
        let allowedUses = [".startOfDay(", ".isDateInToday(", ".firstWeekday", "calendar: Calendar = .current) -> Bool",
                           "convertCalendarYears(recordedIn: Calendar.current"]
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeTokenBar")
        var offenders: [String] = []
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.contains("Calendar.current") || line.contains("calendar: .current")
                || line.contains("Calendar = .current") || line.contains("Calendar.autoupdatingCurrent") {
                if allowedUses.contains(where: line.contains) { continue }
                offenders.append("\(url.lastPathComponent):\(index + 1)")
            }
        }
        XCTAssertTrue(offenders.isEmpty, "use LocalUsageReader.gregorianCalendar(): \(offenders.joined(separator: ", "))")
    }

    /// [Regression] The years a save kept before the switch were the system calendar's. Read back, a Buddhist 2569
    /// held the birthday gift back 543 years and a Japanese 8 let it and the season's eggs come twice. They are
    /// converted at load; a Gregorian save is left as it is.
    func testYearsKeptInAnotherCalendarAreConvertedAtLoad() {
        let zone = TimeZone(identifier: "Europe/Paris")!
        let now = DateComponents(calendar: LocalUsageReader.gregorianCalendar(timeZone: zone),
                                 year: 2026, month: 10, day: 29, hour: 12).date!
        func converted(_ identifier: Calendar.Identifier, gift: Int, eggs: Set<String>) -> CompanionState {
            var calendar = Calendar(identifier: identifier)
            calendar.timeZone = zone
            var state = CompanionState()
            state.lastBirthdayGiftYear = gift
            state.birthdayChangedAfterGiftYear = gift
            state.claimedEventEggs = eggs
            state.convertCalendarYears(recordedIn: calendar, now: now)
            return state
        }
        let buddhist = converted(.buddhist, gift: 2569, eggs: ["autumn@2569", "halloween@2568"])
        XCTAssertEqual(buddhist.lastBirthdayGiftYear, 2026)
        XCTAssertEqual(buddhist.birthdayChangedAfterGiftYear, 2026)
        XCTAssertEqual(buddhist.claimedEventEggs, ["autumn@2026", "halloween@2025"])
        let japanese = converted(.japanese, gift: 8, eggs: ["autumn@8"])
        XCTAssertEqual(japanese.lastBirthdayGiftYear, 2026)
        XCTAssertEqual(japanese.claimedEventEggs, ["autumn@2026"])
        XCTAssertEqual(converted(.persian, gift: 1405, eggs: []).lastBirthdayGiftYear, 2026)
        XCTAssertEqual(converted(.hebrew, gift: 5787, eggs: []).lastBirthdayGiftYear, 2026, "never after this year")
        let gregorian = converted(.gregorian, gift: 2025, eggs: ["autumn@2026"])
        XCTAssertEqual(gregorian.lastBirthdayGiftYear, 2025)
        XCTAssertEqual(gregorian.claimedEventEggs, ["autumn@2026"])
        XCTAssertEqual(converted(.buddhist, gift: 2026, eggs: ["autumn@2026"]).claimedEventEggs, ["autumn@2026"],
                       "already converted: left as it is")
    }
}

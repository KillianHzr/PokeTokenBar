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
        let allowedUses = [".startOfDay(", ".isDateInToday(", ".firstWeekday", "calendar: Calendar = .current) -> Bool"]
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
}

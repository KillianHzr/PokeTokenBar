import XCTest
@testable import PokeTokenBar

/// The changelog: every day once, newest first, every change in the eight languages; the days after the last one
/// seen are new, a player who never looked sees the latest day as new, and opening it counts everything seen.
@MainActor
final class ChangelogTests: XCTestCase {
    func testTheDaysRunNewestFirstOnce() {
        let dates = Changelog.days.map(\.date)
        XCTAssertEqual(dates, dates.sorted(by: >))
        XCTAssertEqual(Set(dates).count, dates.count, "each day once")
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        for day in Changelog.days {
            XCTAssertNotNil(parser.date(from: day.date), day.date)
            XCTAssertFalse(day.entries.isEmpty, day.date)
        }
        XCTAssertEqual(dates.last, "2026-10-14", "the fork's first day")
    }

    /// Every change reads in every language, without the dashes the texts never use, and each language its own.
    func testEveryChangeIsWrittenInEveryLanguage() {
        for day in Changelog.days {
            for (index, entry) in day.entries.enumerated() {
                let texts = AppLanguage.allCases.map { entry.text(L($0)) }
                for (language, text) in zip(AppLanguage.allCases, texts) {
                    XCTAssertFalse(text.trimmingCharacters(in: .whitespaces).isEmpty, "\(day.date) #\(index) \(language)")
                    XCTAssertFalse(text.contains("—") || text.contains("–"), "\(day.date) #\(index) \(language): \(text)")
                }
                XCTAssertEqual(texts.count, Set(texts).count, "\(day.date) #\(index): a language left untranslated")
            }
        }
    }

    func testTheDaysAfterTheLastSeenAreNew() {
        let latest = Changelog.days[0].date
        XCTAssertEqual(Changelog.days(after: nil).count, Changelog.days.count)
        XCTAssertTrue(Changelog.days(after: latest).isEmpty)
        XCTAssertEqual(Changelog.days(after: Changelog.initialSeen).map(\.date), [latest])
        XCTAssertEqual(Changelog.title("2026-10-26", language: .fr), "26 octobre 2026")
        XCTAssertEqual(Changelog.title("2026-10-26", language: .en), "October 26, 2026")
    }

    /// A player who never opened it sees the latest day as new; opening it counts every day seen, on this Mac.
    func testOpeningItCountsEverythingSeen() throws {
        let suite = "changelog-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        func store() -> UsageStore { UsageStore(providers: [], autoRefresh: false, defaults: defaults) }
        let first = store()
        XCTAssertEqual(first.unseenChangelogDays.map(\.date), [Changelog.days[0].date])
        first.markChangelogSeen()
        XCTAssertTrue(first.unseenChangelogDays.isEmpty)
        XCTAssertTrue(store().unseenChangelogDays.isEmpty, "kept across launches")
        defaults.set("2026-10-20", forKey: "changelogSeen")
        XCTAssertEqual(store().unseenChangelogDays.map(\.date), Changelog.days.map(\.date).filter { $0 > "2026-10-20" },
                       "after an update, every day since the last visit")
    }
}

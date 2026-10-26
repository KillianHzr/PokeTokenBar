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

    /// Every entry has its own id, unique, its day first: what a player has seen is kept by it.
    func testEveryEntryHasItsOwnID() {
        let ids = Changelog.entries.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "each id once")
        for day in Changelog.days {
            for entry in day.entries {
                XCTAssertTrue(entry.id.hasPrefix(day.date + "-"), entry.id)
            }
        }
        XCTAssertTrue(Changelog.firstRelease.isSubset(of: Changelog.ids), "the first release's ids still exist")
    }

    func testTheEntriesNotSeenAreNew() {
        XCTAssertEqual(Changelog.unseen([]).count, Changelog.entries.count)
        XCTAssertTrue(Changelog.unseen(Changelog.ids).isEmpty)
        XCTAssertEqual(Set(Changelog.unseen(Changelog.initialSeen).map(\.id)), Set(Changelog.days[0].entries.map(\.id)),
                       "a player who never opened it: the latest day")
        XCTAssertEqual(Changelog.title("2026-10-26", language: .fr), "26 octobre 2026")
        XCTAssertEqual(Changelog.title("2026-10-26", language: .en), "October 26, 2026")
    }

    /// A change added to a day already read is new after the update that brings it: the player who read October 26
    /// with the first release sees the changes merged since, and only those.
    func testAChangeAddedToADayAlreadyReadIsNew() throws {
        let suite = "changelog-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        func store() -> UsageStore { UsageStore(providers: [], autoRefresh: false, defaults: defaults) }

        defaults.set("2026-10-26", forKey: UsageStore.changelogSeenDayKey)   // the first release's key
        let since = Set(store().unseenChangelogEntries.map(\.id))
        XCTAssertTrue(since.isSuperset(of: ["2026-10-26-track-line-form", "2026-10-26-stone-egg-duplicates"]))
        XCTAssertTrue(since.isDisjoint(with: Changelog.firstRelease), "what the first release showed stays read")
        XCTAssertTrue(since.allSatisfy { $0 >= "2026-10-26" })

        let updated = store()
        updated.markChangelogSeen()
        XCTAssertTrue(store().unseenChangelogEntries.isEmpty, "kept across launches")
        // A later update adds one more change to the same day.
        var seen = Set(try XCTUnwrap(defaults.stringArray(forKey: UsageStore.changelogSeenKey)))
        seen.remove("2026-10-26-stone-egg-duplicates")
        defaults.set(Array(seen), forKey: UsageStore.changelogSeenKey)
        XCTAssertEqual(store().unseenChangelogEntries.map(\.id), ["2026-10-26-stone-egg-duplicates"])
    }

    /// A player who never opened it sees the latest day as new; opening it counts every change seen, on this Mac.
    func testOpeningItCountsEverythingSeen() throws {
        let suite = "changelog-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        func store() -> UsageStore { UsageStore(providers: [], autoRefresh: false, defaults: defaults) }
        let first = store()
        XCTAssertEqual(first.unseenChangelogEntries.map(\.id), Changelog.days[0].entries.map(\.id))
        first.markChangelogSeen()
        XCTAssertTrue(first.unseenChangelogEntries.isEmpty)
        XCTAssertTrue(store().unseenChangelogEntries.isEmpty, "kept across launches")
    }
}

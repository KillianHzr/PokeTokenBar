import XCTest
@testable import PokeTokenBar

private struct BirthdayProvider: PokeProviding {
    var entries: [BaseSpecies]
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        let legendary = entries.first { $0.id == baseSpeciesID }?.isLegendary == true
        return EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []),
                       rarity: legendary ? .legendary : .common, names: [:])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { entries }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { entries.first { $0.id == id } }
}

/// The birthday gift (#65): the Birthday Egg, claimable for a week from the birthday, or for three months by a save
/// that never got one, once a year; it hatches a mythical not graduated yet, then a legendary, then a shiny one.
@MainActor
final class BirthdayGiftTests: XCTestCase {
    private let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func at(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func claimable(_ birthday: Birthday?, lastGift: Int?, _ now: Date) -> (Int, BirthdayGift.Occasion)? {
        BirthdayGift.claimable(birthday: birthday, lastGiftYear: lastGift, now: now, calendar: utc).map { ($0.year, $0.occasion) }
    }

    /// A week from the birthday for a player who already got gifts; three months for a first one.
    func testTheGiftWaitsAWeekOrThreeMonthsTheFirstTime() throws {
        let march10 = try XCTUnwrap(Birthday(month: 3, day: 10))
        XCTAssertNil(claimable(nil, lastGift: nil, at(2027, 3, 10)), "no birthday, no gift")
        XCTAssertNil(claimable(march10, lastGift: 2026, at(2027, 3, 9)), "not yet")
        XCTAssertEqual(claimable(march10, lastGift: 2026, at(2027, 3, 10, hour: 0))?.0, 2027)
        XCTAssertEqual(claimable(march10, lastGift: 2026, at(2027, 3, 16, hour: 23))?.1, .birthday)
        XCTAssertNil(claimable(march10, lastGift: 2026, at(2027, 3, 17, hour: 0)), "a week has passed")
        XCTAssertNil(claimable(march10, lastGift: 2027, at(2027, 3, 10)), "once a year")

        XCTAssertEqual(claimable(march10, lastGift: nil, at(2027, 3, 12))?.1, .birthday)
        XCTAssertEqual(claimable(march10, lastGift: nil, at(2027, 6, 9))?.1, .belated, "never got one: three months")
        XCTAssertEqual(claimable(march10, lastGift: nil, at(2027, 6, 9))?.0, 2027)
        XCTAssertNil(claimable(march10, lastGift: nil, at(2027, 6, 10, hour: 1)), "three months have passed")
        XCTAssertNil(claimable(march10, lastGift: 2026, at(2027, 5, 1)), "the catch-up is for a first gift only")
    }

    /// February 29 comes on February 28 in other years; a birthday in late December claimed in January counts for
    /// the year before.
    func testLeapDaysAndTheTurnOfTheYear() throws {
        let leap = try XCTUnwrap(Birthday(month: 2, day: 29))
        XCTAssertEqual(claimable(leap, lastGift: 2026, at(2027, 2, 28))?.0, 2027)
        XCTAssertNil(claimable(leap, lastGift: 2027, at(2028, 2, 28)), "2028 has its own February 29")
        XCTAssertEqual(claimable(leap, lastGift: 2027, at(2028, 2, 29))?.0, 2028)

        let december30 = try XCTUnwrap(Birthday(month: 12, day: 30))
        XCTAssertEqual(claimable(december30, lastGift: 2025, at(2027, 1, 2))?.0, 2026)
        XCTAssertEqual(claimable(december30, lastGift: 2026, at(2027, 12, 30))?.0, 2027, "the next one still comes")

        XCTAssertNil(Birthday(month: 4, day: 31))
        XCTAssertNil(Birthday(month: 13, day: 1))
    }

    /// The save keeps the birthday and the last year gifted; a day that cannot exist is dropped, not the save.
    func testTheSaveKeepsTheBirthday() throws {
        var st = CompanionState()
        st.birthday = Birthday(month: 7, day: 14)
        st.lastBirthdayGiftYear = 2026
        let kept = try JSONDecoder().decode(CompanionState.self, from: JSONEncoder().encode(st))
        XCTAssertEqual(kept.birthday, Birthday(month: 7, day: 14))
        XCTAssertEqual(kept.lastBirthdayGiftYear, 2026)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(st)) as? [String: Any])
        json["birthday"] = ["month": 2, "day": 31]
        let read = try JSONDecoder().decode(CompanionState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(read.birthday)
        XCTAssertEqual(read.lastBirthdayGiftYear, 2026)
    }

    // MARK: The store

    private let now = Date(timeIntervalSince1970: 1_793_000_000)
    /// Two mythicals, a legendary and a common line.
    private let bases = [BaseSpecies(id: 151, captureRate: 45, isUnbreedableLegendary: true),
                         BaseSpecies(id: 251, captureRate: 45, isUnbreedableLegendary: true),
                         BaseSpecies(id: 144, captureRate: 3, isUnbreedableLegendary: true),
                         BaseSpecies(id: 1, captureRate: 45)]

    private func store(seed: UInt64 = 1, _ edit: (inout CompanionState) -> Void) throws -> CompanionStore {
        var st = CompanionState()
        st.installBaselineSet = true
        st.lastDate = "2026-10-26"
        edit(&st)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("birthday-\(UUID().uuidString).json")
        try JSONEncoder().encode(st).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return CompanionStore(provider: BirthdayProvider(entries: bases), clock: { self.now }, fileURL: url,
                              rng: SeededRNG(seed: seed))
    }

    private var todaysBirthday: Birthday {
        let parts = Calendar.current.dateComponents([.month, .day], from: now)
        return Birthday(month: parts.month!, day: parts.day!)!
    }

    private func graduated(_ ids: [Int]) -> [DexEntry] {
        ids.map { DexEntry(baseID: $0, finalID: $0, chainOrder: [$0], rarity: .legendary, caughtAt: now) }
    }

    /// The gift goes to the Bag once; changing the date the same year brings no second one.
    func testTheGiftIsClaimedOncePerYear() throws {
        let s = try store { _ in }
        XCTAssertNil(s.birthdayGift)
        s.setBirthday(todaysBirthday)
        let year = Calendar.current.component(.year, from: now)
        XCTAssertEqual(s.birthdayGift?.year, year)
        XCTAssertEqual(s.birthdayGift?.occasion, .birthday)
        XCTAssertTrue(s.claimBirthdayGift())
        XCTAssertEqual(s.itemCount(.birthdayEgg), 1)
        XCTAssertEqual(s.state.lastBirthdayGiftYear, year)
        XCTAssertNil(s.birthdayGift)
        XCTAssertFalse(s.claimBirthdayGift())
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let parts = Calendar.current.dateComponents([.month, .day], from: yesterday)
        s.setBirthday(Birthday(month: parts.month!, day: parts.day!))
        if Calendar.current.component(.year, from: yesterday) == year {
            XCTAssertNil(s.birthdayGift, "another date the same year brings nothing")
        }
        XCTAssertFalse(ItemKind.birthdayEgg.isAchievement)
        XCTAssertNil(ItemKind.birthdayEgg.shopPrice, "never sold")
        XCTAssertEqual(BagView.Section.of(.birthdayEgg), .items)
    }

    /// A new date after a gift never brings a second egg within a year. A December 30 gift claimed on January 2
    /// counts for the year before; moved to February 1, the birthday would bring another in February.
    func testANewDateAfterAGiftWaitsForALaterYear() throws {
        let february = try XCTUnwrap(Birthday(month: 2, day: 1))
        let gift = { (changed: Int?, now: Date) in
            BirthdayGift.claimable(birthday: february, lastGiftYear: 2026, changedAfterGiftYear: changed, now: now,
                                   calendar: self.utc)?.year
        }
        XCTAssertEqual(gift(nil, at(2027, 2, 3)), 2027, "a player who kept February 1 gets it")
        XCTAssertNil(gift(2027, at(2027, 2, 3)), "changed after a gift claimed in January 2027")
        XCTAssertEqual(gift(2027, at(2028, 2, 3)), 2028)

        // In the app: the claim's calendar year is kept, and a change after it waits for a later birthday year.
        let s = try store { _ in }
        s.setBirthday(todaysBirthday)
        XCTAssertTrue(s.claimBirthdayGift())
        let year = Calendar.current.component(.year, from: now)
        XCTAssertEqual(s.state.lastBirthdayGiftClaimedAt, now)
        XCTAssertNil(s.state.birthdayChangedAfterGiftYear, "no change yet")
        let earlier = Calendar.current.date(byAdding: .day, value: -2, to: now)!
        let parts = Calendar.current.dateComponents([.month, .day], from: earlier)
        s.setBirthday(Birthday(month: parts.month!, day: parts.day!))
        XCTAssertEqual(s.state.birthdayChangedAfterGiftYear, year)
        XCTAssertNil(s.birthdayGift)
        let kept = try JSONDecoder().decode(CompanionState.self, from: JSONEncoder().encode(s.state))
        XCTAssertEqual(kept.birthdayChangedAfterGiftYear, year)
        XCTAssertEqual(kept.lastBirthdayGiftClaimedAt, now)
    }

    /// Used, it sends off the Pokémon for the Birthday Egg, which hatches a mythical while one is missing.
    private func hatch(seed: UInt64, graduated ids: [Int], also: [DexEntry] = []) async throws -> MonState {
        let s = try store(seed: seed) {
            $0.dex = self.graduated(ids) + also
            $0.active = MonState(baseID: 1, pathIDs: [1], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
            $0.inventory = [ItemKind.birthdayEgg.rawValue: 1]
        }
        XCTAssertTrue(s.useBirthdayEgg())
        XCTAssertEqual(s.eggKind, .birthday)
        XCTAssertNil(s.eggGuarantee, "it doesn't tell what hatches")
        s.setEggUsageForTesting(s.eggHatchThreshold)
        await s.hatchIfNeeded()
        XCTAssertFalse(s.state.eggFromBirthdayEgg, "consumed by the hatch")
        XCTAssertFalse(s.state.pendingShiny)
        return try XCTUnwrap(s.state.active, "seed \(seed)")
    }

    func testTheEggHatchesAMissingMythicalThenALegendaryThenAShiny() async throws {
        var mythicals = Set<Int>()
        for seed: UInt64 in 1...12 { mythicals.insert(try await hatch(seed: seed, graduated: []).baseID) }
        XCTAssertEqual(mythicals, [151, 251], "only mythicals, each as likely")

        for seed: UInt64 in 1...6 {
            let missing = try await hatch(seed: seed, graduated: [151])
            XCTAssertEqual(missing.baseID, 251, "the mythical still missing")
            let legend = try await hatch(seed: seed, graduated: [151, 251])
            XCTAssertEqual(legend.baseID, 144, "every mythical graduated: a legendary")
        }

        var every = Set<Int>()
        for seed: UInt64 in 1...16 {
            let mon = try await hatch(seed: seed, graduated: [151, 251, 144])
            XCTAssertTrue(mon.isShiny, "all graduated: a shiny one")
            XCTAssertTrue([151, 251, 144].contains(mon.baseID))
            every.insert(mon.baseID)
        }
        XCTAssertGreaterThan(every.count, 1)
    }

    /// A released mythical is not graduated: it can still come from the egg.
    func testAReleasedMythicalCanStillCome() async throws {
        var released = graduated([151])[0]
        released.releasedAt = now
        for seed: UInt64 in 1...4 {
            let mon = try await hatch(seed: seed, graduated: [251], also: [released])
            XCTAssertEqual(mon.baseID, 151)
        }
        XCTAssertEqual(SpeciesGoal.mythicals.count, 22)
        XCTAssertTrue(Set(SpeciesGoal.mythicals).isDisjoint(with: [144, 150, 249, 250, 384]))
    }
}

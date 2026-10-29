import Foundation

/// The eggs of the year's events: each comes with a banner during its event and waits two more weeks for a player who
/// was away, once a year. What hatches is the event's: its Pokémon, often always shiny.
enum EventEgg: String, CaseIterable, Codable, Sendable {
    case newYear, valentine, pokemonDay, easter, halloween, christmas
    /// The anniversary of the player's very first catch: that Pokémon again, shiny.
    case companion
    case spring, summer, autumn, winter

    /// Days after the event's last one an egg still waits. A season's egg waits the whole season, then the next
    /// season's takes over.
    var claimDays: Int { isSeason ? 0 : 14 }

    var isSeason: Bool { seasonForm != nil }

    /// The event's days in `year`: from its first day to the start of the day after its last. Nil for the companion's
    /// anniversary without a first catch, or in the first catch's own year.
    func days(in year: Int, firstCatch: Date?, calendar: Calendar) -> (start: Date, end: Date)? {
        func day(_ y: Int, _ m: Int, _ d: Int) -> Date? { calendar.date(from: DateComponents(year: y, month: m, day: d)) }
        func span(_ start: Date?, days: Int) -> (start: Date, end: Date)? {
            guard let start, let end = calendar.date(byAdding: .day, value: days, to: start) else { return nil }
            return (start, end)
        }
        func season(_ start: Date?, until end: Date?) -> (start: Date, end: Date)? {
            guard let start, let end else { return nil }
            return (start, end)
        }
        switch self {
        case .newYear: return span(day(year - 1, 12, 31), days: 4)       // December 31 to January 3
        case .valentine: return span(day(year, 2, 12), days: 5)          // February 12 to 16
        case .pokemonDay: return span(day(year, 2, 25), days: 5)         // February 25 to March 1, the 27th its heart
        case .easter:                                                    // Good Friday to Easter Monday
            let sunday = Self.easterSunday(year)
            return span(day(year, sunday.month, sunday.day).flatMap { calendar.date(byAdding: .day, value: -2, to: $0) }, days: 4)
        case .halloween: return span(day(year, 10, 25), days: 7)         // October 25 to 31
        case .christmas: return span(day(year, 12, 20), days: 7)         // December 20 to 26
        case .companion:
            guard let firstCatch else { return nil }
            let parts = calendar.dateComponents([.year, .month, .day], from: firstCatch)
            guard let first = parts.year, year > first, let m = parts.month, let d = parts.day else { return nil }
            // February 29 comes on February 28 in other years.
            let valid = calendar.range(of: .day, in: .month, for: day(year, m, 1) ?? firstCatch)?.contains(d) ?? true
            return span(day(year, m, valid ? d : d - 1), days: 1)
        // A season's egg comes any day of it, once: a player who first opens the app in November still gets the
        // autumn's. It used to come for three days, and none of 2026's autumn came, gone before the eggs shipped.
        case .spring: return season(day(year, 3, 20), until: day(year, 6, 21))
        case .summer: return season(day(year, 6, 21), until: day(year, 9, 22))
        case .autumn: return season(day(year, 9, 22), until: day(year, 12, 21))
        case .winter: return season(day(year, 12, 21), until: day(year + 1, 3, 20))
        }
    }

    /// Easter Sunday of a year (the Gregorian computus).
    static func easterSunday(_ year: Int) -> (month: Int, day: Int) {
        let a = year % 19, b = year / 100, c = year % 100, d = b / 4, e = b % 4
        let f = (b + 8) / 25, g = (b - f + 1) / 3, h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7, m = (a + 11 * h + 22 * l) / 451
        let n = h + l - 7 * m + 114
        return (n / 31, n % 31 + 1)
    }

    /// The ledger key of this event's egg for a year ("christmas@2026").
    func key(year: Int) -> String { "\(rawValue)@\(year)" }

    /// The eggs claimable at `now`, earliest event first: during the event or the two weeks after it, not claimed yet.
    static func claimable(now: Date, claimed: Set<String>, firstCatch: Date?, calendar: Calendar) -> [(egg: EventEgg, year: Int)] {
        let year = calendar.component(.year, from: now)
        var out: [(egg: EventEgg, year: Int, start: Date)] = []
        for egg in allCases {
            // A December event still waits in January; the New Year's starts in December.
            for y in [year - 1, year, year + 1] where !claimed.contains(egg.key(year: y)) {
                guard let days = egg.days(in: y, firstCatch: firstCatch, calendar: calendar),
                      let last = calendar.date(byAdding: .day, value: egg.claimDays, to: days.end),
                      now >= days.start, now < last else { continue }
                out.append((egg, y, days.start))
            }
        }
        return out.sorted { $0.start < $1.start }.map { ($0.egg, $0.year) }
    }

    /// Whether the event is on now, not in the two weeks after it: the banner wishes it then.
    func isOn(year: Int, now: Date, firstCatch: Date?, calendar: Calendar) -> Bool {
        guard let days = days(in: year, firstCatch: firstCatch, calendar: calendar) else { return false }
        return now >= days.start && now < days.end
    }

    // MARK: What hatches

    var item: ItemKind {
        switch self {
        case .newYear: return .newYearEgg
        case .valentine: return .valentineEgg
        case .pokemonDay: return .pokemonDayEgg
        case .easter: return .easterEgg
        case .halloween: return .halloweenEgg
        case .christmas: return .christmasEgg
        case .companion: return .companionEgg
        case .spring: return .springEgg
        case .summer: return .summerEgg
        case .autumn: return .autumnEgg
        case .winter: return .winterEgg
        }
    }

    init?(item: ItemKind) {
        guard let egg = Self.allCases.first(where: { $0.item == item }) else { return nil }
        self = egg
    }

    /// Every one hatches shiny, but the New Year's legendary and the seasons'.
    var alwaysShiny: Bool {
        switch self {
        case .newYear, .spring, .summer, .autumn, .winter: return false
        default: return true
        }
    }

    /// The guarantees the egg keeps like the Shop's and the stones' (`CompanionStore.chooseBase`): Christmas, an Ice
    /// Pokémon rare or better; Halloween, a Ghost one; a season's, Uncommon or better (asked on 2026-10-29), its
    /// Deerling of the season, a Common, kept as the exception (`CompanionStore.chooseBase` rolls it first).
    var tier: Rarity? {
        switch self {
        case .christmas: return .rare
        case .spring, .summer, .autumn, .winter: return .uncommon
        default: return nil
        }
    }
    var type: PokemonType? {
        switch self {
        case .christmas: return .ice
        case .halloween: return .ghost
        default: return nil
        }
    }

    /// The lines of the Pokémon of love and of Easter's eggs and rabbits.
    static let valentineLines: Set<Int> = [370, 594, 682, 527, 440, 856, 669, 905]
    static let easterLines: Set<Int> = [102, 175, 440, 427, 659, 813, 298]
    /// The baby bases of later generations whose lines grow into Kanto Pokémon: Pichu, Cleffa, Igglybuff, Tyrogue,
    /// Smoochum, Elekid, Magby, Mime Jr., Happiny and Munchlax. Pokémon Day's egg took number 151 or lower only, which
    /// left out Pikachu, Clefairy, Jigglypuff, the Hitmons, Jynx, Electabuzz, Magmar, Mr. Mime, Chansey and Snorlax.
    static let kantoBabyLines: Set<Int> = [172, 173, 174, 236, 238, 239, 240, 439, 440, 446]
    static let deerlingID = 585

    /// The types of a season's Pokémon.
    var seasonTypes: [PokemonType] {
        switch self {
        case .spring: return [.grass, .fairy, .bug]
        case .summer: return [.fire, .water, .electric]
        case .autumn: return [.ghost, .dark, .ground]
        case .winter: return [.ice, .steel, .dragon]
        default: return []
        }
    }

    /// Deerling's form for a season.
    var seasonForm: PokemonForm? {
        switch self {
        case .spring: return PokemonForm("spring")
        case .summer: return PokemonForm("summer")
        case .autumn: return PokemonForm("autumn")
        case .winter: return PokemonForm("winter")
        default: return nil
        }
    }

    /// A season's egg hatches Deerling one time in this many, in the season's form.
    static let deerlingOdds: UInt64 = 3

    /// Whether a base line can hatch from this egg (the tier and type guarantees apart). `companionLine`: the line of
    /// the player's first catch.
    /// The lines of an egg that names them, which `admits` keeps alone: nil for an egg of a type, a region or every
    /// legendary.
    func lines(companionLine: Int?) -> Set<Int>? {
        switch self {
        case .valentine: return Self.valentineLines
        case .easter: return Self.easterLines
        case .companion: return companionLine.map { [$0] } ?? []
        case .newYear, .pokemonDay, .halloween, .christmas, .spring, .summer, .autumn, .winter: return nil
        }
    }

    func admits(_ base: BaseSpecies, companionLine: Int?) -> Bool {
        switch self {
        case .newYear: return base.isLegendary
        case .valentine: return Self.valentineLines.contains(base.id)
        case .pokemonDay: return base.id <= 151 || Self.kantoBabyLines.contains(base.id)
        case .easter: return Self.easterLines.contains(base.id)
        case .halloween, .christmas: return true
        case .companion: return base.id == companionLine
        case .spring, .summer, .autumn, .winter:
            return seasonTypes.contains { PokemonTypeData.canHatch(baseID: base.id, as: $0) }
        }
    }
}

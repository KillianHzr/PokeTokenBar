import Foundation

public enum QuestIcon: String, Codable, Sendable {
    case pokeBall = "poke-ball"
    case greatBall = "great-ball"
    case ultraBall = "ultra-ball"
    case masterBall = "master-ball"
    case rareCandy = "rare-candy"
    case mint = "mental-herb"
    case shinyCharm = "shiny-charm"
    case fireStone = "fire-stone"
    case redChain = "red-chain"
    case thunderStone = "thunder-stone"
    case leafStone = "leaf-stone"
    case sunStone = "sun-stone"
    case moonStone = "moon-stone"
    case egg = "egg"
    case azureFlute = "azure-flute"
    case silverWing = "silver-wing"
    case oldSeaMap = "old-sea-map"
    case clearBell = "clear-bell"
    case rainbowWing = "rainbow-wing"
    case magmaStone = "magma-stone"
    case soulDew = "soul-dew"
    case jadeOrb = "jade-orb"
    case gracidea = "gracidea"
    case griseousOrb = "griseous-orb"
    case libertyPass = "liberty-pass"
    case revealGlass = "reveal-glass"
    case dnaSplicers = "dna-splicers"

    public var fallbackEmoji: String {
        switch self {
        case .pokeBall: return "🔴"
        case .greatBall: return "🔵"
        case .ultraBall: return "🟡"
        case .masterBall: return "🟣"
        case .rareCandy: return "🍬"
        case .mint: return "🍃"
        case .shinyCharm: return "✨"
        case .fireStone: return "🔥"
        case .redChain: return "⛓️"
        case .thunderStone: return "⚡"
        case .leafStone: return "🌿"
        case .sunStone: return "☀️"
        case .moonStone: return "🌙"
        case .egg: return "🥚"
        case .azureFlute: return "🪈"
        case .silverWing: return "🪶"
        case .oldSeaMap: return "🗺️"
        case .clearBell: return "🔔"
        case .rainbowWing: return "🌈"
        case .magmaStone: return "🌋"
        case .soulDew: return "💧"
        case .jadeOrb: return "🟢"
        case .gracidea: return "🌸"
        case .griseousOrb: return "🔮"
        case .libertyPass: return "🎟️"
        case .revealGlass: return "🪞"
        case .dnaSplicers: return "🧬"
        }
    }
}

public struct QuestReward: Codable, Sendable, Equatable {
    public let candies: Int
    public let tokens: Int
    public let item: String?

    public init(candies: Int = 0, tokens: Int = 0, item: String? = nil) {
        self.candies = candies
        self.tokens = tokens
        self.item = item
    }
}

public enum DailyQuestType: String, Codable, Sendable, CaseIterable {
    case warmup = "daily_warmup"
    case focus = "daily_focus"
    case power = "daily_power"
    case deepWork = "daily_deep_work"
    case marathon = "daily_marathon"
    case titan = "daily_titan"
    case streak = "daily_streak"
    case incubator = "daily_incubator"

    public var target: Int {
        switch self {
        case .warmup: return 10_000_000
        case .focus: return 50_000_000
        case .power: return 100_000_000
        case .deepWork: return 150_000_000
        case .marathon: return 300_000_000
        case .titan: return 500_000_000
        case .streak: return 1
        case .incubator: return 10_000_000
        }
    }

    public var icon: QuestIcon {
        switch self {
        case .warmup: return .pokeBall
        case .focus: return .greatBall
        case .power: return .ultraBall
        case .deepWork: return .rareCandy
        case .marathon: return .ultraBall
        case .titan: return .masterBall
        case .streak: return .redChain
        case .incubator: return .egg
        }
    }

    public var reward: QuestReward {
        switch self {
        case .warmup: return QuestReward(tokens: 250_000)
        case .focus: return QuestReward(tokens: 1_000_000)
        case .power: return QuestReward(tokens: 2_000_000)
        case .deepWork: return QuestReward(candies: 1, tokens: 4_000_000)
        case .marathon: return QuestReward(candies: 1, tokens: 8_000_000)
        case .titan: return QuestReward(candies: 2, tokens: 15_000_000)
        case .streak: return QuestReward(tokens: 500_000)
        case .incubator: return QuestReward(tokens: 500_000)
        }
    }
}

public struct DailyQuestItem: Identifiable, Sendable {
    public let type: DailyQuestType
    public var id: String { type.rawValue }
    public let progress: Int
    public let target: Int
    public let isCompleted: Bool
    public let isClaimed: Bool

    public init(type: DailyQuestType, progress: Int, isClaimed: Bool) {
        self.type = type
        self.target = type.target
        self.progress = min(progress, type.target)
        self.isCompleted = progress >= type.target
        self.isClaimed = isClaimed
    }
}

public enum WeeklyQuestType: String, Codable, Sendable, CaseIterable {
    case activeDays3 = "weekly_active_3"
    case activeDays5 = "weekly_active_5"
    case tokens100M = "weekly_tokens_100m"
    case tokens300M = "weekly_tokens_300m"
    case tokens1B = "weekly_tokens_1b"
    case tokens2B = "weekly_tokens_2b"
    case tokens3_5B = "weekly_tokens_3_5b"

    public var target: Int {
        switch self {
        case .activeDays3: return 3
        case .activeDays5: return 5
        case .tokens100M: return 100_000_000
        case .tokens300M: return 300_000_000
        case .tokens1B: return 1_000_000_000
        case .tokens2B: return 2_000_000_000
        case .tokens3_5B: return 3_500_000_000
        }
    }

    public var icon: QuestIcon {
        switch self {
        case .activeDays3: return .leafStone
        case .activeDays5: return .sunStone
        case .tokens100M: return .greatBall
        case .tokens300M: return .ultraBall
        case .tokens1B: return .rareCandy
        case .tokens2B: return .moonStone
        case .tokens3_5B: return .masterBall
        }
    }

    public var reward: QuestReward {
        switch self {
        case .activeDays3: return QuestReward(tokens: 1_000_000)
        case .activeDays5: return QuestReward(candies: 1, tokens: 3_000_000)
        case .tokens100M: return QuestReward(tokens: 2_500_000)
        case .tokens300M: return QuestReward(tokens: 6_000_000)
        case .tokens1B: return QuestReward(candies: 1, tokens: 12_000_000)
        case .tokens2B: return QuestReward(candies: 2, tokens: 20_000_000)
        case .tokens3_5B: return QuestReward(candies: 3, tokens: 35_000_000)
        }
    }
}

public struct WeeklyQuestItem: Identifiable, Sendable {
    public let type: WeeklyQuestType
    public var id: String { type.rawValue }
    public let progress: Int
    public let target: Int
    public let isCompleted: Bool
    public let isClaimed: Bool

    public init(type: WeeklyQuestType, progress: Int, isClaimed: Bool) {
        self.type = type
        self.target = type.target
        self.progress = min(progress, type.target)
        self.isCompleted = progress >= type.target
        self.isClaimed = isClaimed
    }
}

public enum AchievementType: String, Codable, Sendable, CaseIterable {
    case firstHatch = "ach_first_hatch"
    case firstEvolve = "ach_first_evolve"
    case firstGraduate = "ach_first_graduate"
    case squad5 = "ach_squad_5"
    case dex15 = "ach_dex_15"
    case dex30 = "ach_dex_30"
    case shinyHunter = "ach_shiny_hunter"
    case streak3 = "ach_streak_3"
    case streak7 = "ach_streak_7"
    case streak14 = "ach_streak_14"
    case streak30 = "ach_streak_30"
    case tokens100M = "ach_tokens_100m"
    case tokens1B = "ach_tokens_1b"
    case tokens5B = "ach_tokens_5b"
    case tokens10B = "ach_tokens_10b"
    case candyUser = "ach_candy_user"
    case shopSpender = "ach_shop_spender"
    case limitBreaker = "ach_limit_breaker"
    case duplicateLegendary = "ach_duplicate_legendary"
    case legendaryBirds = "ach_legendary_birds"
    case kantoDuo = "ach_kanto_duo"
    case legendaryBeasts = "ach_legendary_beasts"
    case towerDuo = "ach_tower_duo"
    case legendaryTitans = "ach_legendary_titans"
    case eonDuo = "ach_eon_duo"
    case weatherTrio = "ach_weather_trio"
    case lakeGuardians = "ach_lake_guardians"
    case creationTrio = "ach_creation_trio"
    case swordsOfJustice = "ach_swords_of_justice"
    case forcesOfNature = "ach_forces_of_nature"
    case taoDuo = "ach_tao_duo"

    public var icon: QuestIcon {
        switch self {
        case .firstHatch: return .egg
        case .firstEvolve: return .thunderStone
        case .firstGraduate: return .masterBall
        case .squad5: return .greatBall
        case .dex15: return .ultraBall
        case .dex30: return .masterBall
        case .shinyHunter: return .shinyCharm
        case .streak3: return .fireStone
        case .streak7: return .leafStone
        case .streak14: return .thunderStone
        case .streak30: return .sunStone
        case .tokens100M: return .pokeBall
        case .tokens1B: return .greatBall
        case .tokens5B: return .ultraBall
        case .tokens10B: return .masterBall
        case .candyUser: return .rareCandy
        case .shopSpender: return .mint
        case .limitBreaker: return .moonStone
        case .duplicateLegendary: return .azureFlute
        case .legendaryBirds: return .silverWing
        case .kantoDuo: return .oldSeaMap
        case .legendaryBeasts: return .clearBell
        case .towerDuo: return .rainbowWing
        case .legendaryTitans: return .magmaStone
        case .eonDuo: return .soulDew
        case .weatherTrio: return .jadeOrb
        case .lakeGuardians: return .gracidea
        case .creationTrio: return .griseousOrb
        case .swordsOfJustice: return .libertyPass
        case .forcesOfNature: return .revealGlass
        case .taoDuo: return .dnaSplicers
        }
    }

    public var target: Int {
        switch self {
        case .firstHatch: return 1
        case .firstEvolve: return 1
        case .firstGraduate: return 1
        case .squad5: return 5
        case .dex15: return 15
        case .dex30: return 30
        case .shinyHunter: return 1
        case .streak3: return 3
        case .streak7: return 7
        case .streak14: return 14
        case .streak30: return 30
        case .tokens100M: return 100_000_000
        case .tokens1B: return 1_000_000_000
        case .tokens5B: return 5_000_000_000
        case .tokens10B: return 10_000_000_000
        case .candyUser: return 5
        case .shopSpender: return 1_000_000_000
        case .limitBreaker: return 1
        case .duplicateLegendary: return 2
        case .legendaryBirds: return 3
        case .kantoDuo: return 2
        case .legendaryBeasts: return 3
        case .towerDuo: return 2
        case .legendaryTitans: return 3
        case .eonDuo: return 2
        case .weatherTrio: return 3
        case .lakeGuardians: return 3
        case .creationTrio: return 3
        case .swordsOfJustice: return 3
        case .forcesOfNature: return 3
        case .taoDuo: return 2
        }
    }

    public var reward: QuestReward {
        switch self {
        case .firstHatch: return QuestReward(candies: 1)
        case .firstEvolve: return QuestReward(candies: 1, tokens: 5_000_000)
        case .firstGraduate: return QuestReward(candies: 1, tokens: 10_000_000)
        case .squad5: return QuestReward(candies: 2, tokens: 25_000_000)
        case .dex15: return QuestReward(candies: 3, tokens: 50_000_000)
        case .dex30: return QuestReward(candies: 5, tokens: 100_000_000)
        case .shinyHunter: return QuestReward(candies: 3, tokens: 50_000_000)
        case .streak3: return QuestReward(tokens: 2_000_000)
        case .streak7: return QuestReward(candies: 1, tokens: 5_000_000)
        case .streak14: return QuestReward(candies: 2, tokens: 15_000_000)
        case .streak30: return QuestReward(candies: 3, tokens: 30_000_000)
        case .tokens100M: return QuestReward(tokens: 5_000_000)
        case .tokens1B: return QuestReward(candies: 1, tokens: 25_000_000)
        case .tokens5B: return QuestReward(candies: 2, tokens: 50_000_000)
        case .tokens10B: return QuestReward(candies: 3, tokens: 100_000_000)
        case .candyUser: return QuestReward(tokens: 10_000_000)
        case .shopSpender: return QuestReward(tokens: 25_000_000)
        case .limitBreaker: return QuestReward(candies: 1, tokens: 5_000_000)
        case .duplicateLegendary: return QuestReward(item: ItemKind.legendCharm.rawValue)
        case .legendaryBirds: return QuestReward(item: ItemKind.silverWing.rawValue)
        case .kantoDuo: return QuestReward(item: ItemKind.oldSeaMap.rawValue)
        case .legendaryBeasts: return QuestReward(item: ItemKind.clearBell.rawValue)
        case .towerDuo: return QuestReward(item: ItemKind.rainbowWing.rawValue)
        case .legendaryTitans: return QuestReward(item: ItemKind.magmaStone.rawValue)
        case .eonDuo: return QuestReward(item: ItemKind.soulDew.rawValue)
        case .weatherTrio: return QuestReward(item: ItemKind.jadeOrb.rawValue)
        case .lakeGuardians: return QuestReward(item: ItemKind.gracidea.rawValue)
        case .creationTrio: return QuestReward(item: ItemKind.griseousOrb.rawValue)
        case .swordsOfJustice: return QuestReward(item: ItemKind.libertyPass.rawValue)
        case .forcesOfNature: return QuestReward(item: ItemKind.revealGlass.rawValue)
        case .taoDuo: return QuestReward(item: ItemKind.dnaSplicers.rawValue)
        }
    }
}

public struct AchievementItem: Identifiable, Sendable {
    public let type: AchievementType
    public var id: String { type.rawValue }
    public let progress: Int
    public let target: Int
    public let isCompleted: Bool
    public let isClaimed: Bool

    public init(type: AchievementType, progress: Int, isClaimed: Bool) {
        self.type = type
        self.target = type.target
        self.progress = min(progress, type.target)
        self.isCompleted = progress >= type.target
        self.isClaimed = isClaimed
    }
}

public struct QuestState: Codable, Sendable, Equatable {
    public var dailyQuestDate: String = ""
    public var weeklyQuestKey: String = ""
    public var claimedDailyQuestIDs: Set<String> = []
    public var claimedWeeklyQuestIDs: Set<String> = []
    public var claimedAchievementIDs: Set<String> = []
    public var currentStreak: Int = 0
    public var bestStreak: Int = 0
    public var lastActiveDate: String = ""
    public var weeklyActiveDays: Set<String> = []
    public var weeklyTokens: Int = 0
    public var totalCandiesUsed: Int = 0
    public var limitsHitCount: Int = 0

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dailyQuestDate = (try? c.decode(String.self, forKey: .dailyQuestDate)) ?? ""
        weeklyQuestKey = (try? c.decode(String.self, forKey: .weeklyQuestKey)) ?? ""
        claimedDailyQuestIDs = (try? c.decode(Set<String>.self, forKey: .claimedDailyQuestIDs)) ?? []
        claimedWeeklyQuestIDs = (try? c.decode(Set<String>.self, forKey: .claimedWeeklyQuestIDs)) ?? []
        claimedAchievementIDs = (try? c.decode(Set<String>.self, forKey: .claimedAchievementIDs)) ?? []
        currentStreak = (try? c.decode(Int.self, forKey: .currentStreak)) ?? 0
        bestStreak = (try? c.decode(Int.self, forKey: .bestStreak)) ?? 0
        lastActiveDate = (try? c.decode(String.self, forKey: .lastActiveDate)) ?? ""
        weeklyActiveDays = (try? c.decode(Set<String>.self, forKey: .weeklyActiveDays)) ?? []
        weeklyTokens = (try? c.decode(Int.self, forKey: .weeklyTokens)) ?? 0
        totalCandiesUsed = (try? c.decode(Int.self, forKey: .totalCandiesUsed)) ?? 0
        limitsHitCount = (try? c.decode(Int.self, forKey: .limitsHitCount)) ?? 0
    }
}

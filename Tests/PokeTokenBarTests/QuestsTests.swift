import XCTest
@testable import PokeTokenBar

private func questNode(_ id: Int, _ ch: [EvoNode] = []) -> EvoNode { EvoNode(speciesID: id, children: ch) }
private func questLine(base: Int) -> EvoLine {
    EvoLine(baseID: base, tree: questNode(base), rarity: .common,
            names: [base: ["en": "P\(base)", "ko": "포\(base)", "fr": "P\(base)"]])
}
private struct QuestStubProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { questLine(base: baseSpeciesID) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: 1, captureRate: 255)] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { BaseSpecies(id: id, captureRate: 255) }
}

@MainActor
final class QuestsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore(used: Int = 0, spent: Int = 0) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("quests-\(UUID().uuidString).json")
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":\(used),\"spentTokens\":\(spent),"
            + "\"lastDate\":\"2026-09-15\",\"active\":null,\"dex\":[],\"collectedFinals\":[]}"
        try? json.data(using: .utf8)!.write(to: url)
        return CompanionStore(provider: QuestStubProvider(), clock: { self.now }, fileURL: url)
    }

    func testInitialQuestState() {
        let store = makeStore()
        XCTAssertEqual(store.currentStreak, 0)
        XCTAssertEqual(store.bestStreak, 0)
        XCTAssertFalse(store.isStreakActiveToday)
        XCTAssertEqual(store.dailyQuests.count, DailyQuestType.allCases.count)
        XCTAssertEqual(store.weeklyQuests.count, WeeklyQuestType.allCases.count)
        XCTAssertEqual(store.achievements.count, AchievementType.allCases.count)
    }

    func testStreakProgressionAndReset() {
        let store = makeStore()

        // Day 1
        store.update(todayTokensByProvider: ["claude": 10_000_000], todayDate: "2026-09-15",
                     monthTotal: 10_000_000, burnTier: .normal, limitWarning: false, hasUsageData: true)
        XCTAssertEqual(store.currentStreak, 1)
        XCTAssertEqual(store.bestStreak, 1)
        XCTAssertTrue(store.isStreakActiveToday)

        // Same day activity does not advance streak
        store.update(todayTokensByProvider: ["claude": 20_000_000], todayDate: "2026-09-15",
                     monthTotal: 20_000_000, burnTier: .normal, limitWarning: false, hasUsageData: true)
        XCTAssertEqual(store.currentStreak, 1)

        // Consecutive Day (Day 2)
        store.update(todayTokensByProvider: ["claude": 5_000_000], todayDate: "2026-09-16",
                     monthTotal: 25_000_000, burnTier: .normal, limitWarning: false, hasUsageData: true)
        XCTAssertEqual(store.currentStreak, 2)
        XCTAssertEqual(store.bestStreak, 2)

        // Skipped day: Day 4 (missed Day 3)
        store.update(todayTokensByProvider: ["claude": 5_000_000], todayDate: "2026-09-18",
                     monthTotal: 30_000_000, burnTier: .normal, limitWarning: false, hasUsageData: true)
        XCTAssertEqual(store.currentStreak, 1)
        XCTAssertEqual(store.bestStreak, 2)
    }

    func testDailyQuestCompletionAndClaim() {
        let store = makeStore()
        store.update(todayTokensByProvider: ["claude": 30_000_000], todayDate: "2026-09-15",
                     monthTotal: 30_000_000, burnTier: .normal, limitWarning: false, hasUsageData: true)

        let warmup = store.dailyQuests.first { $0.type == .warmup }!
        XCTAssertTrue(warmup.isCompleted)
        XCTAssertFalse(warmup.isClaimed)

        let initialCandies = store.rareCandyCount
        let initialTokens = store.availableTokens

        // Claim warmup
        let claimed = store.claimDailyQuest(.warmup)
        XCTAssertTrue(claimed)

        let updatedWarmup = store.dailyQuests.first { $0.type == .warmup }!
        XCTAssertTrue(updatedWarmup.isClaimed)
        XCTAssertEqual(store.availableTokens, initialTokens + DailyQuestType.warmup.reward.tokens)
        XCTAssertEqual(store.rareCandyCount, initialCandies + DailyQuestType.warmup.reward.candies)

        // Double claim should fail
        XCTAssertFalse(store.claimDailyQuest(.warmup))
    }

    func testDeepWork150MRewardHasCandy() {
        let store = makeStore()
        XCTAssertEqual(DailyQuestType.deepWork.reward.candies, 1)

        store.update(todayTokensByProvider: ["claude": 150_000_000], todayDate: "2026-09-15",
                     monthTotal: 150_000_000, burnTier: .normal, limitWarning: false, hasUsageData: true)

        let deepWork = store.dailyQuests.first { $0.type == .deepWork }!
        XCTAssertTrue(deepWork.isCompleted)
        XCTAssertFalse(deepWork.isClaimed)

        let candyBefore = store.rareCandyCount
        XCTAssertTrue(store.claimDailyQuest(.deepWork))
        XCTAssertEqual(store.rareCandyCount, candyBefore + 1)
    }

    func testWeeklyQuestsProgressionAndReset() {
        let store = makeStore()

        // Week 1 - Day 1
        store.update(todayTokensByProvider: ["claude": 50_000_000], todayDate: "2026-09-15",
                     monthTotal: 50_000_000, burnTier: .normal, limitWarning: false, hasUsageData: true,
                     weekTotal: 50_000_000)

        // Week 1 - Day 2
        store.update(todayTokensByProvider: ["claude": 60_000_000], todayDate: "2026-09-16",
                     monthTotal: 110_000_000, burnTier: .normal, limitWarning: false, hasUsageData: true,
                     weekTotal: 110_000_000)

        let weekly100M = store.weeklyQuests.first { $0.type == .tokens100M }!
        XCTAssertTrue(weekly100M.isCompleted)
        XCTAssertFalse(weekly100M.isClaimed)

        XCTAssertTrue(store.claimWeeklyQuest(.tokens100M))
        let updatedWeekly = store.weeklyQuests.first { $0.type == .tokens100M }!
        XCTAssertTrue(updatedWeekly.isClaimed)

        // Week 2 transition
        store.update(todayTokensByProvider: ["claude": 5_000_000], todayDate: "2026-09-22",
                     monthTotal: 115_000_000, burnTier: .normal, limitWarning: false, hasUsageData: true,
                     weekTotal: 5_000_000)

        let newWeekQuest = store.weeklyQuests.first { $0.type == .tokens100M }!
        XCTAssertFalse(newWeekQuest.isClaimed)
        XCTAssertFalse(newWeekQuest.isCompleted)
    }

    func testDailyAndWeeklyMaxMilestones() {
        let store = makeStore()
        XCTAssertEqual(DailyQuestType.titan.target, 500_000_000)
        XCTAssertEqual(DailyQuestType.titan.reward.candies, 2)
        XCTAssertEqual(WeeklyQuestType.tokens3_5B.target, 3_500_000_000)
        XCTAssertEqual(WeeklyQuestType.tokens3_5B.reward.candies, 3)

        store.update(todayTokensByProvider: ["claude": 500_000_000], todayDate: "2026-09-15",
                     monthTotal: 500_000_000, burnTier: .blazing, limitWarning: false, hasUsageData: true,
                     weekTotal: 3_500_000_000)

        let dailyTitan = store.dailyQuests.first { $0.type == .titan }!
        XCTAssertTrue(dailyTitan.isCompleted)

        let weekly3_5B = store.weeklyQuests.first { $0.type == .tokens3_5B }!
        XCTAssertTrue(weekly3_5B.isCompleted)
    }

    func testBatchClaimAll() {
        let store = makeStore(used: 150_000_000)
        store.update(todayTokensByProvider: ["claude": 30_000_000], todayDate: "2026-09-15",
                     monthTotal: 30_000_000, burnTier: .normal, limitWarning: false, hasUsageData: true)

        let claimedQuestsCount = store.claimAllQuests()
        XCTAssertGreaterThan(claimedQuestsCount, 0)

        let claimedAchCount = store.claimAllAchievements()
        XCTAssertGreaterThan(claimedAchCount, 0)
    }

    func testAchievementsClaim() {
        let store = makeStore(used: 150_000_000)

        let ach100M = store.achievements.first { $0.type == .tokens100M }!
        XCTAssertTrue(ach100M.isCompleted)
        XCTAssertFalse(ach100M.isClaimed)

        let initialCandies = store.rareCandyCount
        let initialTokens = store.availableTokens
        let claimed = store.claimAchievement(.tokens100M)
        XCTAssertTrue(claimed)

        XCTAssertEqual(store.rareCandyCount, initialCandies + AchievementType.tokens100M.reward.candies)
        XCTAssertEqual(store.availableTokens, initialTokens + AchievementType.tokens100M.reward.tokens)
        let updatedAch = store.achievements.first { $0.type == .tokens100M }!
        XCTAssertTrue(updatedAch.isClaimed)

        // Double claim should fail
        XCTAssertFalse(store.claimAchievement(.tokens100M))
    }

    func testDuplicateLegendaryAchievementAndLegendCharm() {
        let store = makeStore()

        let achInitial = store.achievements.first { $0.type == .duplicateLegendary }!
        XCTAssertEqual(achInitial.progress, 0)
        XCTAssertFalse(achInitial.isCompleted)
        XCTAssertFalse(achInitial.isClaimed)
        XCTAssertFalse(store.ownsLegendCharm)

        // Having 1 Mewtwo graduated -> progress 1
        let mewtwo1 = DexEntry(baseID: 150, finalID: 150, chainOrder: [150], rarity: .legendary, caughtAt: now)
        store.addDexEntry(mewtwo1)
        let ach1 = store.achievements.first { $0.type == .duplicateLegendary }!
        XCTAssertEqual(ach1.progress, 1)
        XCTAssertFalse(ach1.isCompleted)

        // Having a different legendary (Rayquaza) -> progress is still 1 (not duplicate yet)
        let rayquaza = DexEntry(baseID: 384, finalID: 384, chainOrder: [384], rarity: .legendary, caughtAt: now)
        store.addDexEntry(rayquaza)
        let achStill1 = store.achievements.first { $0.type == .duplicateLegendary }!
        XCTAssertEqual(achStill1.progress, 1)
        XCTAssertFalse(achStill1.isCompleted)

        // Graduating a 2nd Mewtwo (duplicate legendary raised) -> progress 2!
        let mewtwo2 = DexEntry(baseID: 150, finalID: 150, chainOrder: [150], rarity: .legendary, caughtAt: now)
        store.addDexEntry(mewtwo2)
        let ach2 = store.achievements.first { $0.type == .duplicateLegendary }!
        XCTAssertEqual(ach2.progress, 2)
        XCTAssertTrue(ach2.isCompleted)
        XCTAssertFalse(ach2.isClaimed)

        let candyBefore = store.rareCandyCount
        let tokensBefore = store.availableTokens
        XCTAssertTrue(store.claimAchievement(.duplicateLegendary))

        XCTAssertTrue(store.ownsLegendCharm)
        XCTAssertEqual(store.itemCount(.legendCharm), 1)
        XCTAssertEqual(store.rareCandyCount, candyBefore)
        XCTAssertEqual(store.availableTokens, tokensBefore)

        let achClaimed = store.achievements.first { $0.type == .duplicateLegendary }!
        XCTAssertTrue(achClaimed.isClaimed)
        XCTAssertFalse(store.claimAchievement(.duplicateLegendary))
    }

    func testLegendaryGroupAchievementsAndPassiveItems() {
        let store = makeStore()

        // Legendary birds (144, 145, 146)
        let bird1 = DexEntry(baseID: 144, finalID: 144, chainOrder: [144], rarity: .legendary, caughtAt: now)
        let bird2 = DexEntry(baseID: 145, finalID: 145, chainOrder: [145], rarity: .legendary, caughtAt: now)
        store.addDexEntries([bird1, bird2])

        let birdsAch = store.achievements.first { $0.type == .legendaryBirds }!
        XCTAssertEqual(birdsAch.progress, 2)
        XCTAssertFalse(birdsAch.isCompleted)

        let bird3 = DexEntry(baseID: 146, finalID: 146, chainOrder: [146], rarity: .legendary, caughtAt: now)
        store.addDexEntry(bird3)

        let birdsAchComplete = store.achievements.first { $0.type == .legendaryBirds }!
        XCTAssertEqual(birdsAchComplete.progress, 3)
        XCTAssertTrue(birdsAchComplete.isCompleted)

        XCTAssertTrue(store.claimAchievement(.legendaryBirds))
        XCTAssertTrue(store.ownsSilverWing)

        // Silver wing halves hatch threshold
        let defaultThreshold = PokemonBalance.scaled(PokemonBalance.eggHatchThreshold, by: store.growthDifficulty)
        XCTAssertEqual(store.eggTokensToHatch, max(1_000_000, defaultThreshold / 2))

        // Tao duo (Reshiram 643, Zekrom 644)
        let reshiram = DexEntry(baseID: 643, finalID: 643, chainOrder: [643], rarity: .legendary, caughtAt: now)
        let zekrom = DexEntry(baseID: 644, finalID: 644, chainOrder: [644], rarity: .legendary, caughtAt: now)
        store.addDexEntries([reshiram, zekrom])

        let taoAch = store.achievements.first { $0.type == .taoDuo }!
        XCTAssertEqual(taoAch.progress, 2)
        XCTAssertTrue(taoAch.isCompleted)
        XCTAssertTrue(store.claimAchievement(.taoDuo))
        XCTAssertTrue(store.ownsDnaSplicers)
    }

    func testQuestStateLenientDecoding() throws {
        let legacyJson = "{\"installBaselineSet\":true,\"usedSinceInstall\":50000000,\"spentTokens\":0,"
            + "\"lastDate\":\"2026-09-15\",\"active\":null,\"dex\":[],\"collectedFinals\":[]}"
        let decoded = try JSONDecoder().decode(CompanionState.self, from: legacyJson.data(using: .utf8)!)
        XCTAssertEqual(decoded.questState.currentStreak, 0)
        XCTAssertEqual(decoded.questState.bestStreak, 0)
        XCTAssertTrue(decoded.questState.claimedDailyQuestIDs.isEmpty)
        XCTAssertTrue(decoded.questState.claimedWeeklyQuestIDs.isEmpty)
    }
}

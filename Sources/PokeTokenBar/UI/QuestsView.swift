import SwiftUI

@MainActor
struct QuestsView: View {
    let store: CompanionStore
    let nav: PopoverNavigation
    @State private var selectedSegment = 0

    private var l: L { store.l }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            streakBanner

            Picker("", selection: $selectedSegment) {
                Text(store.unclaimedQuestsTabCount > 0 ? "\(l.quests) (\(store.unclaimedQuestsTabCount))" : l.quests).tag(0)
                Text(store.unclaimedAchievementsCount > 0 ? "\(l.achievements) (\(store.unclaimedAchievementsCount))" : l.achievements).tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            actionBar

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if selectedSegment == 0 {
                        questsContent
                    } else {
                        achievementsList
                    }
                }
                .padding(.bottom, 6)
            }
            .frame(height: 440)
        }
    }

    private var streakBanner: some View {
        HStack(spacing: 12) {
            QuestIconView(icon: .redChain, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(l.streakTitle(days: store.currentStreak))
                        .font(.callout.weight(.bold))
                    Spacer()
                    Text(l.bestStreakTitle(days: store.bestStreak))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(store.isStreakActiveToday ? l.streakActiveToday : l.streakInactiveToday)
                    .font(.caption)
                    .foregroundStyle(store.isStreakActiveToday ? Color.green : Color.secondary)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var actionBar: some View {
        HStack {
            if selectedSegment == 0 {
                Text(l.quests)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                if store.unclaimedQuestsTabCount > 0 {
                    Button("\(l.claimAll) (\(store.unclaimedQuestsTabCount))") {
                        _ = store.claimAllQuests()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            } else {
                Text(l.achievements)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                if store.unclaimedAchievementsCount > 0 {
                    Button("\(l.claimAll) (\(store.unclaimedAchievementsCount))") {
                        _ = store.claimAllAchievements()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.orange)
                }
            }
        }
    }

    private var questsContent: some View {
        let activeDaily = store.dailyQuests.filter { !$0.isClaimed }
            .sorted { ($0.isCompleted && !$1.isCompleted) }
        let claimedDaily = store.dailyQuests.filter { $0.isClaimed }
        let activeWeekly = store.weeklyQuests.filter { !$0.isClaimed }
            .sorted { ($0.isCompleted && !$1.isCompleted) }
        let claimedWeekly = store.weeklyQuests.filter { $0.isClaimed }
        let totalClaimedCount = claimedDaily.count + claimedWeekly.count

        return VStack(alignment: .leading, spacing: 10) {
            Text(l.dailyQuests)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            if activeDaily.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(l.allDailyQuestsCompleted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                ForEach(activeDaily) { quest in
                    DailyQuestRow(store: store, quest: quest)
                }
            }

            Text(l.weeklyQuests)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            if activeWeekly.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(l.allWeeklyQuestsCompleted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                ForEach(activeWeekly) { quest in
                    WeeklyQuestRow(store: store, quest: quest)
                }
            }

            if totalClaimedCount > 0 {
                Divider().padding(.vertical, 4)
                HStack {
                    Text("\(l.completedQuests) (\(totalClaimedCount))")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                ForEach(claimedDaily) { quest in
                    DailyQuestRow(store: store, quest: quest)
                        .opacity(0.75)
                }

                ForEach(claimedWeekly) { quest in
                    WeeklyQuestRow(store: store, quest: quest)
                        .opacity(0.75)
                }
            }
        }
    }

    private var achievementsList: some View {
        let activeAchievements = store.achievements.filter { !$0.isClaimed }
            .sorted { ($0.isCompleted && !$1.isCompleted) }
        let claimedAchievements = store.achievements.filter { $0.isClaimed }

        return VStack(alignment: .leading, spacing: 10) {
            if activeAchievements.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(.yellow)
                    Text(l.allAchievementsCompleted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                ForEach(activeAchievements) { achievement in
                    AchievementRow(store: store, achievement: achievement)
                }
            }

            if !claimedAchievements.isEmpty {
                Divider().padding(.vertical, 4)
                HStack {
                    Text("\(l.completedAchievements) (\(claimedAchievements.count))")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                ForEach(claimedAchievements) { achievement in
                    AchievementRow(store: store, achievement: achievement)
                        .opacity(0.75)
                }
            }
        }
    }
}

@MainActor
private struct DailyQuestRow: View {
    let store: CompanionStore
    let quest: DailyQuestItem

    private var l: L { store.l }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                QuestIconView(icon: quest.type.icon, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(l.dailyQuestTitle(quest.type))
                            .font(.callout.weight(.semibold))
                        Spacer()
                        rewardBadge(quest.type.reward)
                    }
                    Text(l.dailyQuestDescription(quest.type))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                ProgressView(value: Double(quest.progress), total: Double(quest.target))
                    .tint(.accentColor)
                Text("\(formatNumber(quest.progress)) / \(formatNumber(quest.target))")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                actionButton
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var actionButton: some View {
        if quest.isClaimed {
            Text("✓ " + l.rewardClaimed)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        } else if quest.isCompleted {
            Button(l.claimReward) {
                store.claimDailyQuest(quest.type)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } else {
            Text(l.claimReward)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
    }

    private func formatNumber(_ value: Int) -> String {
        if value >= 1_000_000 {
            return TokenFormatter.compact(value)
        }
        return "\(value)"
    }

    @ViewBuilder
    private func rewardBadge(_ reward: QuestReward) -> some View {
        HStack(spacing: 5) {
            if let item = reward.item, let kind = ItemKind(rawValue: item) {
                HStack(spacing: 3) {
                    ItemIconView(kind: kind, size: 14)
                    Text(l.itemName(kind))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            if reward.candies > 0 {
                HStack(spacing: 3) {
                    ItemIconView(kind: .rareCandy, size: 14)
                    Text("+\(reward.candies)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.primary)
                }
            }
            if reward.tokens > 0 {
                Text("+\(TokenFormatter.compact(reward.tokens))")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.12), in: Capsule())
    }
}

@MainActor
private struct WeeklyQuestRow: View {
    let store: CompanionStore
    let quest: WeeklyQuestItem

    private var l: L { store.l }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                QuestIconView(icon: quest.type.icon, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(l.weeklyQuestTitle(quest.type))
                            .font(.callout.weight(.semibold))
                        Spacer()
                        rewardBadge(quest.type.reward)
                    }
                    Text(l.weeklyQuestDescription(quest.type))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                ProgressView(value: Double(quest.progress), total: Double(quest.target))
                    .tint(.indigo)
                Text("\(formatNumber(quest.progress)) / \(formatNumber(quest.target))")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                actionButton
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var actionButton: some View {
        if quest.isClaimed {
            Text("✓ " + l.rewardClaimed)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        } else if quest.isCompleted {
            Button(l.claimReward) {
                store.claimWeeklyQuest(quest.type)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.indigo)
        } else {
            Text(l.claimReward)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
    }

    private func formatNumber(_ value: Int) -> String {
        if value >= 1_000_000 {
            return TokenFormatter.compact(value)
        }
        return "\(value)"
    }

    @ViewBuilder
    private func rewardBadge(_ reward: QuestReward) -> some View {
        HStack(spacing: 5) {
            if let item = reward.item, let kind = ItemKind(rawValue: item) {
                HStack(spacing: 3) {
                    ItemIconView(kind: kind, size: 14)
                    Text(l.itemName(kind))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            if reward.candies > 0 {
                HStack(spacing: 3) {
                    ItemIconView(kind: .rareCandy, size: 14)
                    Text("+\(reward.candies)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.primary)
                }
            }
            if reward.tokens > 0 {
                Text("+\(TokenFormatter.compact(reward.tokens))")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.12), in: Capsule())
    }
}

@MainActor
private struct AchievementRow: View {
    let store: CompanionStore
    let achievement: AchievementItem

    private var l: L { store.l }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                QuestIconView(icon: achievement.type.icon, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(l.achievementTitle(achievement.type))
                            .font(.callout.weight(.semibold))
                        Spacer()
                        rewardBadge(achievement.type.reward)
                    }
                    Text(l.achievementDescription(achievement.type))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                ProgressView(value: Double(achievement.progress), total: Double(achievement.target))
                    .tint(.orange)
                Text("\(formatNumber(achievement.progress)) / \(formatNumber(achievement.target))")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                actionButton
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var actionButton: some View {
        if achievement.isClaimed {
            Text("✓ " + l.rewardClaimed)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        } else if achievement.isCompleted {
            Button(l.claimReward) {
                store.claimAchievement(achievement.type)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.orange)
        } else {
            Text(l.claimReward)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
    }

    private func formatNumber(_ value: Int) -> String {
        if value >= 1_000_000 {
            return TokenFormatter.compact(value)
        }
        return "\(value)"
    }

    @ViewBuilder
    private func rewardBadge(_ reward: QuestReward) -> some View {
        HStack(spacing: 5) {
            if let item = reward.item, let kind = ItemKind(rawValue: item) {
                HStack(spacing: 3) {
                    ItemIconView(kind: kind, size: 14)
                    Text(l.itemName(kind))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            if reward.candies > 0 {
                HStack(spacing: 3) {
                    ItemIconView(kind: .rareCandy, size: 14)
                    Text("+\(reward.candies)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.primary)
                }
            }
            if reward.tokens > 0 {
                Text("+\(TokenFormatter.compact(reward.tokens))")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.12), in: Capsule())
    }
}

@MainActor
struct QuestIconView: View {
    let icon: QuestIcon
    var size: CGFloat = 30
    @State private var img: NSImage?

    init(icon: QuestIcon, size: CGFloat = 30) {
        self.icon = icon
        self.size = size
        if icon == .egg {
            _img = State(initialValue: SpriteLoader.cachedEggImage())
        } else if icon != .rareCandy {
            _img = State(initialValue: SpriteLoader.cachedItemImage(name: icon.rawValue))
        }
    }

    var body: some View {
        Group {
            if icon == .rareCandy {
                ItemIconView(kind: .rareCandy, size: size)
            } else if let img {
                let fit = SpriteFit.size(for: img.size, box: size)
                Image(nsImage: img).resizable().interpolation(.none)
                    .frame(width: fit.width, height: fit.height)
                    .frame(width: size, height: size)
            } else {
                Text(icon.fallbackEmoji).font(.system(size: size * 0.8))
                    .frame(width: size, height: size)
            }
        }
        .task(id: icon.rawValue) {
            guard img == nil, icon != .rareCandy else { return }
            if icon == .egg {
                if let d = await SpriteStore.shared.eggData(), let loaded = NSImage(data: d) {
                    img = loaded
                }
            } else {
                img = await SpriteLoader.itemImage(name: icon.rawValue)
            }
        }
    }
}

import SwiftUI

/// 업적 화면 (진화의 돌, 체육관 배지, 전설의 유물): 도감 수집 조건을 달성하면 아이템을 무료로 획득.
/// 획득한 아이템은 가방(인벤토리)으로 들어간다: 돌은 소모품 5개, 배지와 유물은 상시 패시브 효과.
@MainActor
struct AchievementsView: View {
    let store: CompanionStore
    let nav: PopoverNavigation

    enum AchievementCategory: Hashable, CaseIterable {
        case evolutionStones
        case gymBadges
        case legendaryArtifacts

        var collectorGroup: CollectorGroup {
            switch self {
            case .evolutionStones: return .evolutionStones
            case .gymBadges: return .gymBadges
            case .legendaryArtifacts: return .legendaryArtifacts
            }
        }
    }

    @State private var selectedCategory: AchievementCategory

    /// Opens on `category`, or on the first section with a reward ready to claim (Stones when none is).
    init(store: CompanionStore, nav: PopoverNavigation, category: AchievementCategory? = nil) {
        self.store = store
        self.nav = nav
        _selectedCategory = State(initialValue: category ?? Self.firstCategoryWithRewards(store) ?? .evolutionStones)
    }

    /// Rewards ready to claim in one section: unlocked and not claimed yet (each badge region counts).
    static func readyCount(_ category: AchievementCategory, _ store: CompanionStore) -> Int {
        store.achievementTally(in: category.collectorGroup).ready
    }

    /// The first section, in tab order, with a reward ready to claim.
    static func firstCategoryWithRewards(_ store: CompanionStore) -> AchievementCategory? {
        AchievementCategory.allCases.first { readyCount($0, store) > 0 }
    }

    /// Where the claim banner leads: the next section after `current` with a reward ready, wrapping around,
    /// so tapping it again walks through every section that has one.
    static func nextCategoryWithRewards(after current: AchievementCategory, _ store: CompanionStore) -> AchievementCategory? {
        let all = AchievementCategory.allCases
        let start = all.firstIndex(of: current) ?? 0
        return (1...all.count).lazy.map { all[(start + $0) % all.count] }.first { readyCount($0, store) > 0 }
    }

    /// Segment label: the section and the rewards waiting there ("Stones ●2"). Never claimed/total, which
    /// read as a number to claim; the section's progress has its own line under the picker.
    static func tabTitle(_ category: AchievementCategory, _ store: CompanionStore) -> String {
        let title = store.l.collectorGroupTitle(category.collectorGroup)
        let ready = readyCount(category, store)
        return ready > 0 ? "\(title) ●\(ready)" : title
    }

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 10) {
            header

            Picker("", selection: $selectedCategory) {
                ForEach(AchievementCategory.allCases, id: \.self) { cat in
                    Text(Self.tabTitle(cat, store)).tag(cat)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            categoryProgress(l)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    let items = store.achievementItems(in: selectedCategory.collectorGroup)
                    ForEach(items, id: \.self) { kind in
                        AchievementCard(store: store, nav: nav, kind: kind)
                    }
                }
                .reservesScrollerLane()
            }
            // No height of its own: the list takes what the header, banner and picker leave of the 520 pt.
        }
        .frame(height: 520)
    }

    /// Progress of the section on screen ("1 of 10 completed").
    private func categoryProgress(_ l: L) -> some View {
        let tally = store.achievementTally(in: selectedCategory.collectorGroup)
        return Text(l.achievementsProgress(tally.claimed, tally.total))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    /// "Stones 1, Artifacts 2": the sections holding a reward, in tab order.
    private func readyBreakdown(_ l: L) -> String {
        AchievementCategory.allCases.compactMap { category in
            let ready = Self.readyCount(category, store)
            return ready > 0 ? "\(l.collectorGroupTitle(category.collectorGroup)) \(ready)" : nil
        }.joined(separator: ", ")
    }

    private var header: some View {
        let l = store.l
        let claimed = store.claimedAchievementsCount
        let total = store.totalAchievementsCount
        let unclaimed = store.unclaimedAchievementsCount

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(l.achievementsTitle)
                    .font(.headline.weight(.bold))
                Spacer()
                Text(l.achievementsProgress(claimed, total))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if unclaimed > 0 {
                HStack(spacing: 8) {
                    // Says where the rewards wait and takes you there: each tap opens the next section with one.
                    Button {
                        if let next = Self.nextCategoryWithRewards(after: selectedCategory, store) {
                            selectedCategory = next
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "gift.fill")
                                .font(.caption)
                            Text(l.readyToClaimSummary(unclaimed, readyBreakdown(l)))
                                .font(.caption.weight(.semibold))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button(l.claimAll) { store.claimAllAchievements() }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.white))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

/// 개별 업적 카드: 아이콘, 이름, 효과 설명, 도감 달성 조건 및 [받기 / 획득함] 버튼.
@MainActor
private struct AchievementCard: View {
    let store: CompanionStore
    let nav: PopoverNavigation
    let kind: ItemKind

    private var isClaimed: Bool {
        store.isClaimed(kind)
    }

    private var canClaim: Bool {
        if kind.badgeType != nil { return readyTiers > 0 }
        return !isClaimed && store.isUnlocked(kind)
    }

    private var readyTiers: Int { store.badgeTiers(kind).filter(\.isReady).count }

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ItemIconView(kind: kind, size: 30)
                    .grayscale(isClaimed || canClaim ? 0 : 1)
                    .opacity(isClaimed || canClaim ? 1 : 0.45)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(l.itemName(kind))
                            .font(.callout.weight(.semibold))

                        if let type = kind.badgeType ?? kind.stoneType {
                            Badge(l.typeName(type).uppercased(), tint: .type(type))
                        }
                        if kind.achievementRewardCount > 1 {
                            Text("×\(kind.achievementRewardCount)").font(.caption.weight(.bold))
                                .foregroundStyle(.secondary).monospacedDigit()
                        }

                        Spacer(minLength: 4)

                        statusAction(l)
                    }

                    Text(l.itemDescription(kind))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let type = kind.badgeType {
                        let maximum = Double(PokemonTypeData.badgeGenerations(for: type).count)
                        Text(l.badgeBonus(Double(store.claimedBadgeTierCount(type)) * CollectorBonus.badgeRegionBonus * 100,
                                          of: maximum * CollectorBonus.badgeRegionBonus * 100))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(store.claimedBadgeTierCount(type) > 0 ? .green : .secondary)
                            .monospacedDigit()
                    }
                }
            }

            if kind.badgeType != nil {
                BadgeRegionGrid(store: store, kind: kind)
            } else {
                UnlockRequirementView(store: store, kind: kind, compact: isClaimed)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func statusAction(_ l: L) -> some View {
        if isClaimed {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
                Text(l.claimed)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
            }
        } else if canClaim {
            Button(readyTiers > 1 ? "\(l.claim) (\(readyTiers))" : l.claim) {
                store.claimAchievement(kind)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } else {
            Label(l.lockedLabel, systemImage: "lock.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

/// The regions of a gym badge: claimed ones checked, complete ones ready to claim, the others with their
/// progress. Each region is the badge type's Pokémon from one generation.
@MainActor
private struct BadgeRegionGrid: View {
    let store: CompanionStore
    let kind: ItemKind

    var body: some View {
        let l = store.l
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), alignment: .leading, spacing: 4) {
            ForEach(store.badgeTiers(kind), id: \.generation) { tier in
                HStack(spacing: 3) {
                    Text(l.regionName(generation: tier.generation))
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 2)
                    status(tier)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(background(tier)))
                .help("\(tier.progress.registered.count)/\(tier.progress.goal.needed)")
            }
        }
    }

    @ViewBuilder
    private func status(_ tier: CompanionStore.BadgeTier) -> some View {
        if tier.isClaimed {
            Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(.green)
        } else if tier.isReady {
            Image(systemName: "gift.fill").font(.caption2).foregroundStyle(Color.accentColor)
        } else {
            Text("\(tier.progress.count)/\(tier.progress.goal.needed)")
                .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func background(_ tier: CompanionStore.BadgeTier) -> Color {
        if tier.isClaimed { return .green.opacity(0.14) }
        if tier.isReady { return Color.accentColor.opacity(0.22) }
        return .secondary.opacity(0.08)
    }
}

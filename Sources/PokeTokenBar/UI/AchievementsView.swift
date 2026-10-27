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
        case forms

        var collectorGroup: CollectorGroup {
            switch self {
            case .evolutionStones: return .evolutionStones
            case .gymBadges: return .gymBadges
            case .legendaryArtifacts: return .legendaryArtifacts
            case .forms: return .forms
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

            PillPicker(selection: $selectedCategory,
                       options: AchievementCategory.allCases.map { ($0, Self.tabTitle($0, store)) })

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

    /// Progress of the section on screen ("1 of 10 completed"), and what counts: graduated Pokémon, not the one
    /// being raised nor those sent off, which stay in the Pokédex.
    private func categoryProgress(_ l: L) -> some View {
        let tally = store.achievementTally(in: selectedCategory.collectorGroup)
        return Text("\(l.achievementsProgress(tally.claimed, tally.total)) · \(l.achievementsGraduatedOnly)")
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
        if kind.isRegional { return readyTiers > 0 }
        return !isClaimed && store.isUnlocked(kind)
    }

    private var readyTiers: Int { store.regionTiers(kind).filter(\.isReady).count }

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

                    Text(l.itemDescription(kind, rareCandyXP: store.rareCandyXP))
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

            if kind == .excavation {
                ExcavationPanel(store: store)
            } else if kind.isRegional {
                RegionGrid(store: store, kind: kind)
            } else {
                UnlockRequirementView(store: store, kind: kind, compact: isClaimed)
            }
        }
        .padding(12)
        .designSurface(cornerRadius: Design.cornerRadius)
    }

    @ViewBuilder
    private func statusAction(_ l: L) -> some View {
        if isClaimed {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.readableGreen)
                Text(l.claimed)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.readableGreen)
            }
        } else if canClaim {
            Button(readyTiers > 1 ? "\(l.claim) (\(readyTiers))" : l.claim) {
                store.claimAchievement(kind)
            }
            .buttonStyle(.pill(prominent: true))
        } else if kind == .excavation {
            // Its eggs say where it stands, under the description.
            EmptyView()
        } else if kind.isRegional {
            // A regional achievement is never locked as a whole: show how many of its regions are claimed.
            let tiers = store.regionTiers(kind)
            Label("\(tiers.filter(\.isDone).count)/\(tiers.count)", systemImage: "map")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        } else {
            Label(l.lockedLabel, systemImage: "lock.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

/// The regions of a regional achievement: claimed ones checked, complete ones ready to claim, the others with their
/// progress. Each region is one generation: a badge type's Pokémon from it, or all of its species.
@MainActor
private struct RegionGrid: View {
    let store: CompanionStore
    let kind: ItemKind

    var body: some View {
        grid(store.regionTiers(kind), store.l)
    }

    private func grid(_ tiers: [CompanionStore.RegionTier], _ l: L) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), alignment: .leading, spacing: 4) {
            ForEach(tiers, id: \.generation) { tier in
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
    private func status(_ tier: CompanionStore.RegionTier) -> some View {
        if tier.isClaimed {
            Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(Color.readableGreen)
        } else if tier.isReady {
            Image(systemName: "gift.fill").font(.caption2).foregroundStyle(Color.accentColor)
        } else {
            Text("\(tier.progress.count)/\(tier.progress.goal.needed)")
                .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func background(_ tier: CompanionStore.RegionTier) -> Color {
        if tier.isClaimed { return .green.opacity(0.14) }
        if tier.isReady { return Color.accentColor.opacity(0.22) }
        return .secondary.opacity(0.08)
    }
}

/// The digs told as eggs: 15, one per fossil line, in the digs' order, each state its own look and named in a legend
/// below. The fossil lines fold away under it: they are what the eggs give, not what the digs ask for, and shown first
/// they read as a goal.
@MainActor
private struct ExcavationPanel: View {
    let store: CompanionStore
    @State private var showsLines = false

    private static let amber = Color(red: 0.93, green: 0.58, blue: 0.16)

    enum Egg: CaseIterable { case opened, inBag, ready, next, toEarn, notClaimable }

    /// The eggs in the digs' order: claimed (opened, then in the Bag), ready, the next one, those to earn, and the
    /// digs done with nothing to claim, which are the last ones.
    static func eggs(_ progress: CompanionStore.ExcavationProgress) -> [Egg] {
        var eggs = Array(repeating: Egg.opened, count: progress.opened) + Array(repeating: .inBag, count: progress.inBag)
        eggs += Array(repeating: .ready, count: progress.ready)
        if progress.toEarn > 0 {
            eggs += (progress.towardNext != nil ? [.next] : [.toEarn])
            eggs += Array(repeating: .toEarn, count: progress.toEarn - 1)
        }
        return eggs + Array(repeating: .notClaimable, count: progress.notClaimable)
    }

    var body: some View {
        let l = store.l
        let progress = store.excavationProgress
        let eggs = Self.eggs(progress)
        let toward = progress.towardNext ?? 0
        // The next egg is one to earn: one entry for both.
        let named = Egg.allCases.filter { kind in kind != .next && eggs.contains { $0 == kind || ($0 == .next && kind == .toEarn) } }
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(20), spacing: 7), count: 10), alignment: .leading,
                      spacing: 7) {
                ForEach(Array(eggs.enumerated()), id: \.offset) { _, egg in
                    look(egg, toward: toward, width: 19)
                        .help(egg == .next ? l.excavationNextEgg(toward, of: FossilDig.rockPerDig) : name(egg, l))
                }
            }
            WrappingHStack(spacing: 10, lineSpacing: 4) {
                ForEach(named, id: \.self) { egg in
                    HStack(spacing: 4) {
                        look(egg, toward: toward, width: 10)
                        Text(name(egg, l)).font(.caption2).foregroundStyle(.secondary)
                    }
                    .fixedSize()
                }
            }
            if progress.towardNext != nil {
                Text(l.excavationNextEgg(toward, of: FossilDig.rockPerDig))
                    .font(.caption.weight(.semibold)).monospacedDigit()
            }
            Button {
                withAnimation(.easeOut(duration: 0.15)) { showsLines.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text(l.excavationLines(progress.linesGraduated, of: FossilDig.lines.count))
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(showsLines ? 90 : 0))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showsLines { lines }
        }
    }

    private func name(_ egg: Egg, _ l: L) -> String {
        switch egg {
        case .opened: l.excavationEggOpened
        case .inBag: l.excavationEggInBag
        case .ready: l.excavationEggReady
        case .next, .toEarn: l.excavationEggToEarn
        case .notClaimable: l.excavationEggNotClaimable
        }
    }

    /// Opened: the bottom of a hatched shell under its faint outline. In the Bag: whole, with a bag. To claim: whole, ringed, with a gift.
    /// The next: filling from the bottom as its Rock-type Pokémon graduate. To earn: an outline. Not claimable: grey,
    /// barred.
    private func look(_ egg: Egg, toward: Int, width: CGFloat) -> some View {
        let height = width * 24 / 19
        let icon = width * 0.42
        let shape = Ellipse()
        return ZStack {
            switch egg {
            case .opened:
                // The shell's missing top, faint, so the bottom half reads as an egg hatched.
                shape.strokeBorder(Self.amber.opacity(0.35), lineWidth: max(1, width / 16))
                shape.fill(Self.amber.opacity(0.85)).mask(OpenedShell())
            case .inBag:
                shape.fill(Self.amber)
                Image(systemName: "bag.fill").font(.system(size: icon)).foregroundStyle(.white)
            case .ready:
                shape.fill(Self.amber)
                shape.strokeBorder(Color.accentColor, lineWidth: max(1, width / 10))
                Image(systemName: "gift.fill").font(.system(size: icon)).foregroundStyle(.white)
            case .next:
                shape.fill(Self.amber.opacity(0.7))
                    .mask(alignment: .bottom) {
                        Rectangle().frame(height: height * CGFloat(toward) / CGFloat(FossilDig.rockPerDig))
                    }
                shape.strokeBorder(Self.amber, lineWidth: max(1, width / 13))
            case .toEarn:
                shape.strokeBorder(Color.secondary.opacity(0.5),
                                   style: StrokeStyle(lineWidth: max(1, width / 16), dash: [width / 8, width / 10]))
            case .notClaimable:
                shape.fill(Color.secondary.opacity(0.25))
                Image(systemName: "nosign").font(.system(size: icon, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
        .frame(width: width, height: height)
    }

    /// The fossil lines, those graduated in color.
    private var lines: some View {
        let graduated = store.graduatedSpeciesIDs
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 8), spacing: 2) {
            ForEach(FossilDig.lines, id: \.self) { line in
                let owned = graduated.contains(line)
                SpriteView(speciesID: line, size: 26, sameScale: true)
                    .frame(width: 28, height: 28)
                    .grayscale(owned ? 0 : 1).opacity(owned ? 1 : 0.35)
                    .speciesNameTooltip(line, language: store.language)
            }
        }
    }
}

/// The bottom of a hatched egg: below a zigzag rim.
private struct OpenedShell: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let rim = rect.minY + rect.height * 0.45
        let teeth = 3
        path.move(to: CGPoint(x: rect.minX, y: rim))
        for index in 1...(teeth * 2) {
            let x = rect.minX + rect.width * CGFloat(index) / CGFloat(teeth * 2)
            path.addLine(to: CGPoint(x: x, y: rim + (index % 2 == 1 ? -rect.height * 0.1 : rect.height * 0.06)))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

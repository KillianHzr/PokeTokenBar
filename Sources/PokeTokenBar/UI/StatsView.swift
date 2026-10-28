import SwiftUI

/// The Stats page, read top to bottom: one week, month or year (its numbers, its days, where its tokens went and who
/// graduated in it), then everything since install (totals, records, the usual week). Each number appears once.
@MainActor
struct StatsScreen: View {
    let store: UsageStore
    let companion: CompanionStore
    let onBack: () -> Void

    @State private var scope: RecapScope = .month
    /// 0 is the running period, -1 the one before it. Never positive: the future has no usage.
    @State private var offset = 0
    /// The bar under the pointer, by bucket key.
    @State private var hovered: String?

    /// Today's bar, as on Home.
    private static let accent = Design.actionColor
    private static let kindColors: [Color] = [
        Color(red: 0.36, green: 0.62, blue: 0.95),   // cache read
        Color(red: 0.62, green: 0.47, blue: 0.92),   // cache write
        Color(red: 0.95, green: 0.62, blue: 0.30),   // input
        Color(red: 0.40, green: 0.78, blue: 0.50),   // output
        Color(red: 0.60, green: 0.62, blue: 0.68),   // unsplit
    ]

    var body: some View {
        let l = companion.l
        let calendar = RecapPeriod.calendar()
        let content = RecapContent(store: store, companion: companion, scope: scope, offset: offset, calendar: calendar)
        let report = StatsReport.make(
            recap: content.recap, ledger: store.dailyLedger, costs: store.dailyCostLedger,
            tools: store.snapshots.compactMap { snapshot in
                snapshot.monthDaily.map {
                    StatsReport.ToolSeries(id: snapshot.providerID, name: snapshot.displayName, days: $0,
                                           reportsCost: snapshot.reportsCost)
                }
            },
            dex: companion.state.dex, now: Date(), calendar: calendar)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button { onBack() } label: {
                    Label(l.back, systemImage: "chevron.left").labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)   // Esc, like Settings: both take over the popover
                Spacer(minLength: 4)
                Text(l.statsTitle).font(.headline)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    periodControls(content, l)
                    summary(report, content, l)
                    if report.recap.total > 0 { chart(report, content, l) }
                    if let breakdown = report.breakdown { whereTokensWent(breakdown, l) }
                    graduates(report, l)
                    sinceInstall(StatsRecords.make(ledger: store.dailyLedger, now: Date(), calendar: calendar)
                        .keeping(store.keptRecords), l)
                }
                .reservesScrollerLane()
            }
            .frame(height: 540)
        }
        .padding(PopoverMetrics.padding)
        .onChange(of: scope) { offset = 0; hovered = nil }
        .onChange(of: offset) { hovered = nil }
    }

    // MARK: The period

    private func periodControls(_ content: RecapContent, _ l: L) -> some View {
        VStack(spacing: 8) {
            Picker(l.recapOpen, selection: $scope) {
                ForEach(RecapScope.allCases, id: \.self) { Text(l.recapScopeName($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            HStack(spacing: 6) {
                Button { offset -= 1 } label: { Image(systemName: "chevron.left").frame(width: 24, height: 20) }
                    .accessibilityLabel(l.recapPrevious)
                    .disabled(!content.recap.canGoBack)
                Spacer(minLength: 4)
                VStack(spacing: 2) {
                    Text(content.periodLabel())
                        .font(.system(.headline, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.8)
                    if offset != 0 {
                        Button(l.recapCurrentPeriod(scope)) { offset = 0 }
                            .font(.caption)
                    }
                }
                Spacer(minLength: 4)
                Button { offset += 1 } label: { Image(systemName: "chevron.right").frame(width: 24, height: 20) }
                    .accessibilityLabel(l.recapNext)
                    .disabled(offset >= 0)
            }
            .buttonStyle(.borderless)
        }
    }

    private func summary(_ report: StatsReport, _ content: RecapContent, _ l: L) -> some View {
        let recap = report.recap
        let cost = store.showsCost ? report.cost : nil
        var tiles: [(String, String)] = []
        if let cost { tiles.append((l.statsCost, TokenFormatter.costCompact(cost))) }
        if recap.activeDays > 0 {
            tiles.append((l.statsPerActiveDay, TokenFormatter.compact(recap.total / recap.activeDays)))
        }
        tiles.append((l.recapActiveDays, "\(recap.activeDays)/\(recap.countedDays)"))
        if cost == nil { tiles.append((l.recapBestStreak, l.recapDays(recap.bestStreak))) }
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(TokenFormatter.compact(recap.total))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(l.recapTokensUnit).font(.callout).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    if let change = report.change { changeChip(change) }
                }
                if recap.total == 0 {
                    Text(l.statsNoUsage).font(.caption).foregroundStyle(.secondary)
                } else if report.change != nil {
                    Text(recap.isInProgress ? l.recapCompareSoFar(scope) : l.statsComparePrevious(scope))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if recap.total > 0 {
                HStack(spacing: 6) {
                    ForEach(tiles, id: \.0) { label, value in tile(label, value) }
                }
            }
            if store.showsCost, cost == nil, recap.total > 0 {
                Label(l.statsCostUnknown, systemImage: "questionmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let projection = report.projection {
                let value = cost != nil && projection.cost != nil
                    ? "\(TokenFormatter.compact(projection.tokens)) (\(TokenFormatter.costCompact(projection.cost ?? 0)))"
                    : TokenFormatter.compact(projection.tokens)
                Label(l.statsProjection(scope, value), systemImage: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .designCard()
    }

    private func changeChip(_ change: Double) -> some View {
        Text("\(change >= 0 ? "▲" : "▼") \(TokenFormatter.percent(abs(change) * 100))")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .monospacedDigit()
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.callout, design: .rounded).weight(.bold))
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Day by day

    private static let track: CGFloat = 96

    private func chart(_ report: StatsReport, _ content: RecapContent, _ l: L) -> some View {
        let buckets = report.recap.buckets
        let peak = buckets.filter(\.hasData).max { $0.tokens < $1.tokens }
        let labels = content.bucketLabels()
        let colors = DailyTrendStack.colorIndices(for: report.breakdown?.tools.map(\.id) ?? [],
                                                  registry: store.registeredProviderIDs,
                                                  paletteCount: MonthDailyTrend.providerPalette.count)
        let spacing: CGFloat = switch scope {
        case .week: 10
        case .month: 2
        case .year: 6
        }
        return VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: scope == .year ? l.statsMonthByMonth : l.statsDayByDay, systemImage: "chart.bar.fill")
            readout(report, content, focus: buckets.first { $0.key == hovered } ?? peak, isPeak: hovered == nil,
                    colors: colors, l)
            VStack(spacing: 4) {
                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(buckets, id: \.key) { bucket in
                        bar(bucket, report: report, peak: max(1, peak?.tokens ?? 1), colors: colors)
                            .frame(maxWidth: .infinity)
                            .frame(height: Self.track, alignment: .bottom)
                            .contentShape(Rectangle())
                            .onHover { inside in
                                if inside, bucket.hasData { hovered = bucket.key } else if hovered == bucket.key { hovered = nil }
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(content.accessibilityLabel(bucket))
                    }
                }
                .background(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.10)).frame(height: 1) }
                HStack(spacing: spacing) {
                    ForEach(Array(buckets.enumerated()), id: \.element.key) { index, bucket in
                        // Zero-width frame: a month's "15" is wider than its column and must not widen it.
                        Text(labels.indices.contains(index) ? labels[index] : "")
                            .font(.system(size: 9, weight: bucket.isCurrent ? .bold : .medium, design: .rounded))
                            .foregroundStyle(bucket.isCurrent ? AnyShapeStyle(Self.accent) : AnyShapeStyle(.secondary))
                            .fixedSize()
                            .frame(width: 0, height: 11)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            if report.stacksByTool, let tools = report.breakdown?.tools {
                WrappingHStack(spacing: 10, lineSpacing: 4) {
                    ForEach(tools, id: \.id) { tool in
                        HStack(spacing: 4) {
                            Circle().fill(toolColor(tool.id, colors)).frame(width: 7, height: 7)
                            Text(tool.name).foregroundStyle(.secondary)
                        }
                        .font(.caption2)
                        .fixedSize()
                    }
                }
            }
        }
        .designCard()
    }

    /// The bar under the pointer, or the period's peak when there is none: its day, tokens, cost, the tools' share
    /// and the Pokémon graduated that day. Two lines, kept whatever it holds so the bars never move.
    private func readout(_ report: StatsReport, _ content: RecapContent, focus: UsageRecap.Bucket?, isPeak: Bool,
                         colors: [String: Int], _ l: L) -> some View {
        let detail = focus.map(report.detail)
        return VStack(alignment: .leading, spacing: 3) {
            if let focus, let detail {
                HStack(spacing: 5) {
                    if isPeak { Text(l.peakDay).foregroundStyle(.secondary) }
                    Text(content.bucketName(focus)).fontWeight(.semibold).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Text(TokenFormatter.compact(detail.tokens)).fontWeight(.bold).monospacedDigit()
                    if store.showsCost, let cost = detail.cost {
                        Text(TokenFormatter.costCompact(cost)).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .font(.system(.callout, design: .rounded))
                HStack(spacing: 8) {
                    if report.stacksByTool {
                        ForEach(detail.tools, id: \.id) { tool in
                            HStack(spacing: 3) {
                                Circle().fill(toolColor(tool.id, colors)).frame(width: 6, height: 6)
                                Text(TokenFormatter.compact(tool.tokens)).monospacedDigit()
                            }
                        }
                    }
                    if detail.graduated > 0 {
                        Label("\(detail.graduated)", systemImage: "graduationcap.fill")
                    }
                    Spacer(minLength: 0)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(height: 38, alignment: .top)
    }

    @ViewBuilder
    private func bar(_ bucket: UsageRecap.Bucket, report: StatsReport, peak: Int, colors: [String: Int]) -> some View {
        let isHovered = hovered == bucket.key
        if !bucket.hasData {
            // The future, or before the app was counting: a place, not a zero.
            Circle().fill(Color.primary.opacity(0.07)).frame(width: 3, height: 3)
        } else if bucket.tokens == 0 {
            Circle().fill(Color.secondary.opacity(0.35)).frame(width: 3, height: 3)
        } else {
            let height = max(3, Self.track * CGFloat(bucket.tokens) / CGFloat(peak))
            let tools = report.stacksByTool ? report.detail(bucket).tools : []
            let shape = UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3, style: .continuous)
            if tools.isEmpty {
                let base = bucket.isCurrent ? Self.accent : Color.primary.opacity(isHovered ? 0.6 : 0.3)
                shape.fill(LinearGradient(colors: [base, base.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                    .frame(height: height)
            } else {
                let total = max(1, tools.reduce(0) { $0 + $1.tokens })
                VStack(spacing: 0) {
                    // `tools` runs largest first, which sits at the bottom.
                    ForEach(tools.reversed(), id: \.id) { tool in
                        toolColor(tool.id, colors)
                            .opacity(bucket.isCurrent || isHovered ? 1 : 0.65)
                            .frame(height: height * CGFloat(tool.tokens) / CGFloat(total))
                    }
                }
                .frame(height: height)
                .clipShape(shape)
            }
        }
    }

    private func toolColor(_ id: String, _ colors: [String: Int]) -> Color {
        MonthDailyTrend.providerPalette[(colors[id] ?? 0) % MonthDailyTrend.providerPalette.count]
    }

    // MARK: Where the tokens went

    private func whereTokensWent(_ breakdown: StatsReport.Breakdown, _ l: L) -> some View {
        let kinds: [(String, Int)] = [
            (l.tokenCacheRead, breakdown.cacheRead), (l.tokenCacheWrite, breakdown.cacheWrite),
            (l.tokenInput, breakdown.input), (l.tokenOutput, breakdown.output), (l.statsUnsplit, breakdown.unsplit),
        ]
        let shown = kinds.enumerated().filter { $0.element.1 > 0 }
        let total = max(1, breakdown.total)
        let colors = DailyTrendStack.colorIndices(for: breakdown.tools.map(\.id), registry: store.registeredProviderIDs,
                                                  paletteCount: MonthDailyTrend.providerPalette.count)
        return VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: l.statsWhereTokensWent, systemImage: "chart.pie.fill")
            GeometryReader { geometry in
                HStack(spacing: 1.5) {
                    ForEach(shown, id: \.offset) { index, kind in
                        Self.kindColors[index]
                            .frame(width: max(2, (geometry.size.width - 1.5 * CGFloat(shown.count - 1))
                                * CGFloat(kind.1) / CGFloat(total)))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 10)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], alignment: .leading,
                      spacing: 4) {
                ForEach(shown, id: \.offset) { index, kind in
                    HStack(spacing: 5) {
                        Circle().fill(Self.kindColors[index]).frame(width: 7, height: 7)
                        Text(kind.0).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 2)
                        Text(TokenFormatter.percent(Double(kind.1) / Double(total) * 100))
                            .fontWeight(.semibold).monospacedDigit()
                    }
                    .font(.caption)
                    .help(TokenFormatter.grouped(kind.1))
                }
            }
            if breakdown.tools.count > 1 {
                Divider()
                Text(l.statsByTool).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(breakdown.tools, id: \.id) { tool in
                    HStack(spacing: 6) {
                        Circle().fill(toolColor(tool.id, colors)).frame(width: 7, height: 7)
                        Text(tool.name).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(TokenFormatter.compact(tool.tokens)).fontWeight(.semibold).monospacedDigit()
                        Text(TokenFormatter.percent(Double(tool.tokens) / Double(total) * 100))
                            .foregroundStyle(.secondary).monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                        if store.showsCost {
                            Text(tool.cost.map(TokenFormatter.costCompact) ?? "")
                                .foregroundStyle(.secondary).monospacedDigit()
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                    .font(.caption)
                }
            }
        }
        .designCard()
    }

    // MARK: Graduates

    private func graduates(_ report: StatsReport, _ l: L) -> some View {
        let shown = report.graduated.prefix(16)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle(text: l.recapGraduates, systemImage: "graduationcap.fill")
                Spacer(minLength: 4)
                Text("\(report.graduated.count)")
                    .font(.system(.callout, design: .rounded).weight(.bold))
                    .monospacedDigit()
            }
            if report.graduated.isEmpty {
                Text(l.recapNoGraduates).font(.caption).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 4) {
                    ForEach(Array(shown), id: \.id) { entry in
                        SpriteView(speciesID: entry.finalID, size: 30, shiny: entry.isShiny, form: entry.form, sameScale: true)
                            .overlay(alignment: .topTrailing) {
                                if entry.isShiny { Text("✨").font(.system(size: 8)) }
                            }
                            .speciesNameTooltip(entry.finalID, form: entry.form, language: companion.language)
                    }
                }
                if report.graduated.count > shown.count {
                    Text("+\(report.graduated.count - shown.count)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .designCard()
    }

    // MARK: Since install

    private func sinceInstall(_ records: StatsRecords, _ l: L) -> some View {
        // Graduated ones: a Pokémon sent off for an egg stays in the Pokédex as a released entry.
        let dex = companion.state.dex.filter { !$0.isReleased }
        let tokens = companion.state.usedSinceInstall
        let shinies = dex.filter(\.isShiny).count
        let legendaries = dex.filter { $0.rarity == .legendary }.count
        var tiles = [(l.statsTokens, TokenFormatter.compact(tokens)), (l.statsPokemon, "\(dex.count)")]
        if !dex.isEmpty { tiles.append((l.statsTokensPerPokemon, TokenFormatter.compact(tokens / dex.count))) }
        let locale = companion.language.displayLocale
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: l.statsSinceInstall, systemImage: "clock.arrow.circlepath")
            HStack(spacing: 6) {
                ForEach(tiles, id: \.0) { label, value in tile(label, value) }
            }
            // Label then count, so one legendary does not read as a plural.
            let rare = [(l.statsShinies, shinies), (l.statsLegendaries, legendaries)].filter { $0.1 > 0 }
            if !rare.isEmpty {
                Text("✨ " + rare.map { "\($0.0) \($0.1)" }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let day = records.bestDay {
                Divider()
                Text(l.statsRecords).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                VStack(spacing: 5) {
                    recordRow(l.recapBestDay, Self.date(day.key, "EEE d MMM y", locale), day.tokens)
                    if let week = records.bestWeek {
                        recordRow(l.statsBestWeek, l.statsWeekOf(Self.date(week.key, "d MMM y", locale)), week.tokens)
                    }
                    if let month = records.bestMonth {
                        recordRow(l.statsBestMonth, Self.date(month.key, "MMMM y", locale), month.tokens)
                    }
                    HStack {
                        Text(l.statsStreak).foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Text(l.statsStreakValue(current: records.currentStreak, longest: records.longestStreak))
                            .fontWeight(.semibold).monospacedDigit()
                    }
                    .font(.caption)
                }
            }
            if let averages = records.weekdayAverages {
                Divider()
                usualWeek(averages, locale: locale, l)
            }
        }
        .designCard()
    }

    private func recordRow(_ label: String, _ when: String, _ tokens: Int) -> some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(when).lineLimit(1).minimumScaleFactor(0.8)
            Text(TokenFormatter.compact(tokens)).fontWeight(.semibold).monospacedDigit()
                .frame(minWidth: 44, alignment: .trailing)
        }
        .font(.caption)
    }

    /// Seven small bars from the first weekday, the busiest one in the accent color.
    private func usualWeek(_ averages: [Int], locale: Locale, _ l: L) -> some View {
        let calendar = RecapPeriod.calendar()
        let formatter = DateFormatter()
        formatter.locale = locale
        let short = formatter.shortStandaloneWeekdaySymbols ?? []
        let names = formatter.standaloneWeekdaySymbols ?? []
        // Symbols run from Sunday; the averages from the calendar's first weekday.
        func symbol(_ slot: Int, _ list: [String]) -> String {
            guard !list.isEmpty else { return "" }
            return list[(slot + calendar.firstWeekday - 1) % list.count]
        }
        let peak = max(1, averages.max() ?? 1)
        let busiest = averages.firstIndex(of: averages.max() ?? 0) ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            Text(l.statsUsualWeek).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(0..<averages.count, id: \.self) { slot in
                    VStack(spacing: 3) {
                        UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3, style: .continuous)
                            .fill(slot == busiest ? Self.accent : Color.primary.opacity(0.3))
                            .frame(height: max(averages[slot] > 0 ? 3 : 0, 40 * CGFloat(averages[slot]) / CGFloat(peak)))
                            .frame(height: 40, alignment: .bottom)
                        Text(String(symbol(slot, short).prefix(2)).uppercased())
                            .font(.system(size: 9, weight: slot == busiest ? .bold : .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .help(TokenFormatter.compact(averages[slot]))
                }
            }
            Text(l.statsBusiestDay(symbol(busiest, names), TokenFormatter.compact(averages[busiest])))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static func date(_ key: String, _ template: String, _ locale: Locale) -> String {
        let calendar = RecapPeriod.calendar()
        let parser = LocalUsageReader.localDayFormatter(timeZone: calendar.timeZone)
        guard let date = parser.date(from: key) else { return key }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}

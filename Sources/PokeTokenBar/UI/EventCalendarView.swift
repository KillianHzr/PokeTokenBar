import SwiftUI

/// The events' calendar (7.6): the eggs on now, to take or taken, the next ones within a year, earliest first, with
/// what each can hatch, and those taken this year. Each state says itself in a word and a glyph (● to take, ✓ taken,
/// "in 52 d"), never in a color alone.
@MainActor
struct EventCalendarScreen: View {
    let store: CompanionStore
    let onBack: () -> Void

    var body: some View {
        let l = store.l
        let calendar = store.eventCalendar()
        let year = LocalUsageReader.gregorianCalendar().component(.year, from: Date())
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button { onBack() } label: {
                    Label(l.back, systemImage: "chevron.left").labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                Spacer(minLength: 4)
                Text(l.calendarTitle).font(.headline)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !calendar.now.isEmpty { section(l.calendarNow, calendar.now, l) }
                    if !calendar.upcoming.isEmpty { section(l.calendarUpcoming, calendar.upcoming, l) }
                    if !calendar.taken.isEmpty { section(l.calendarTaken(year), calendar.taken, l) }
                }
                .reservesScrollerLane()
            }
            .frame(height: 470)
        }
        .padding(PopoverMetrics.padding)
    }

    private func section(_ title: String, _ items: [CompanionStore.CalendarItem], _ l: L) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in row(item, l) }
        }
    }

    private func row(_ item: CompanionStore.CalendarItem, _ l: L) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Group {
                if case .event(let egg) = item.source {
                    SpriteView(speciesID: nil, size: 28, egg: .event(egg))
                } else {
                    SpriteView(speciesID: nil, size: 28, egg: .birthday)
                }
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title(item, l)).font(.callout.weight(.semibold)).lineLimit(1)
                Text("\(dates(item, l)) · \(contents(item, l))")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            status(item, l)
        }
        .padding(8)
        .designSurface(cornerRadius: Design.cornerRadius)
    }

    private func title(_ item: CompanionStore.CalendarItem, _ l: L) -> String {
        if case .event(let egg) = item.source { return l.eventEggName(egg) }
        return l.calendarBirthday
    }

    private func contents(_ item: CompanionStore.CalendarItem, _ l: L) -> String {
        if case .event(let egg) = item.source { return l.eventEggContents(egg) }
        return l.calendarBirthdayContents
    }

    private func dates(_ item: CompanionStore.CalendarItem, _ l: L) -> String {
        let formatter = DateFormatter()
        formatter.locale = store.language.displayLocale
        formatter.calendar = LocalUsageReader.gregorianCalendar()
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        let last = LocalUsageReader.gregorianCalendar().date(byAdding: .day, value: -1, to: item.end) ?? item.start
        return l.calendarDates(formatter.string(from: item.start), formatter.string(from: last))
    }

    @ViewBuilder
    private func status(_ item: CompanionStore.CalendarItem, _ l: L) -> some View {
        switch item.status {
        case .toTake:
            Text(l.calendarToTake).font(.caption2.weight(.bold)).foregroundStyle(Color.readableOrange)
        case .taken(let hatched):
            VStack(alignment: .trailing, spacing: 1) {
                Text(l.calendarTakenMark).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                if let hatched, let name = store.dexSpecies.first(where: { $0.id == hatched })?.name {
                    Text(l.calendarHatched(name)).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
        case .upcoming:
            let days = LocalUsageReader.gregorianCalendar()
                .dateComponents([.day], from: LocalUsageReader.gregorianCalendar().startOfDay(for: Date()), to: item.start).day ?? 0
            Text(l.calendarInDays(days)).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}

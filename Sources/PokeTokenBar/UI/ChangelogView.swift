import SwiftUI

/// What changed in the app, day by day, newest first (`Changelog`); the days the player had not seen yet are marked
/// new.
@MainActor
struct ChangelogScreen: View {
    let l: L
    let language: AppLanguage
    /// The last day seen before the page opened: the days after it are marked new. Nil marks none.
    let newAfter: String?
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button { onBack() } label: {
                    Label(l.back, systemImage: "chevron.left").labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                Spacer(minLength: 4)
                Text(l.changelogTitle).font(.headline)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Changelog.days, id: \.date) { day in
                        dayCard(day)
                    }
                }
                .reservesScrollerLane()
            }
            .frame(height: 470)
        }
        .padding(PopoverMetrics.padding)
    }

    private func dayCard(_ day: ChangelogDay) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(Changelog.title(day.date, language: language)).font(.callout.weight(.semibold))
                if let newAfter, day.date > newAfter {
                    Badge(l.changelogUnseen.uppercased(), tint: .accent).fixedSize()
                }
                Spacer(minLength: 0)
            }
            ForEach(Array(day.entries.enumerated()), id: \.offset) { _, entry in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Badge(l.changelogKind(entry.kind).uppercased(), tint: Self.tint(entry.kind), style: .tinted)
                        .fixedSize()
                    Text(entry.text(l)).font(.caption).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .designCard()
    }

    static func tint(_ kind: ChangelogEntry.Kind) -> BadgeTint {
        switch kind {
        case .new: return .blue
        case .improved: return .orange
        case .fixed: return .secondary
        }
    }
}

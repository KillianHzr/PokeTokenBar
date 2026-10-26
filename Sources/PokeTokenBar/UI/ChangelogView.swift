import SwiftUI

/// What changed in the app, day by day, newest first (`Changelog`); the changes the player had not seen yet, and their
/// days, are marked new.
@MainActor
struct ChangelogScreen: View {
    let l: L
    let language: AppLanguage
    /// The entries seen before the page opened: the others are marked new.
    let seenBefore: Set<String>
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
                if day.entries.contains(where: { !seenBefore.contains($0.id) }) {
                    Badge(l.changelogUnseen.uppercased(), tint: .accent).fixedSize()
                }
                Spacer(minLength: 0)
            }
            ForEach(day.entries, id: \.id) { entry in
                let isNew = !seenBefore.contains(entry.id)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Badge(l.changelogKind(entry.kind).uppercased(), tint: Self.tint(entry.kind), style: .tinted)
                        .fixedSize()
                    Text(entry.text(l)).font(.caption.weight(isNew ? .semibold : .regular))
                        .fixedSize(horizontal: false, vertical: true)
                }
                // A change that came since the last look: a dot on the edge, beside its line.
                .overlay(alignment: .leading) {
                    if isNew { Circle().fill(Color.accentColor).frame(width: 5, height: 5).offset(x: -9) }
                }
                .accessibilityLabel(isNew ? "\(l.changelogUnseen), \(entry.text(l))" : entry.text(l))
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

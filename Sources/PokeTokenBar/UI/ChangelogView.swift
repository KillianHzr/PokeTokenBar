import SwiftUI

/// What changed in the app, update by update, newest first (`Changelog`); the changes the player had not seen yet, and
/// their updates, are marked new.
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

    /// One update (`ChangelogDay`: what one release of the app brought), its changes grouped as new, improved and
    /// fixed rather than one badge per line.
    private func dayCard(_ day: ChangelogDay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "newspaper").font(.caption).foregroundStyle(.secondary)
                Text(l.changelogUpdateTitle(Changelog.title(day.date, language: language))).font(.callout.weight(.semibold))
                if day.entries.contains(where: { !seenBefore.contains($0.id) }) {
                    Badge(l.changelogUnseen.uppercased(), tint: .accent).fixedSize()
                }
                Spacer(minLength: 0)
                Text(l.changelogChangeCount(day.entries.count)).font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(ChangelogEntry.Kind.allCases, id: \.self) { kind in
                let entries = day.entries.filter { $0.kind == kind }
                if !entries.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Badge(l.changelogSection(kind).uppercased(), tint: Self.tint(kind), style: .tinted).fixedSize()
                        ForEach(entries, id: \.id) { entry in
                            let isNew = !seenBefore.contains(entry.id)
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("•").font(.caption).foregroundStyle(.secondary)
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

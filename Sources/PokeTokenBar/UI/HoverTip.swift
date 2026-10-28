import SwiftUI

/// A tip shown on hover, drawn by the nearest `hoverTipHost()` above the hovered view rather than by the system: the
/// system's tooltip waits about a second, and never showed over the faded sprites of the Pokémon still missing. The
/// app's every tooltip is one of these.
struct HoverTip: Equatable {
    /// What a rendering test names to show it without a pointer (`forcedHoverTipID`).
    let id: String
    let title: String
}

private struct HoverTipItem {
    let tip: HoverTip
    let anchor: Anchor<CGRect>
}

private struct HoverTipKey: PreferenceKey {
    static let defaultValue: [HoverTipItem] = []
    static func reduce(value: inout [HoverTipItem], nextValue: () -> [HoverTipItem]) { value += nextValue() }
}

private struct ForcedHoverTipKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// The tip a rendering test shows with no pointer over it (`HoverTip.id`).
    var forcedHoverTipID: String? {
        get { self[ForcedHoverTipKey.self] }
        set { self[ForcedHoverTipKey.self] = newValue }
    }
}

/// The hovered view: its whole box answers the pointer, and after a short pause it hands its tip to the host. The
/// tips of the views inside it are kept, so a hovered sprite inside a hovered card shows its own.
@MainActor
private struct HoverTipSource: ViewModifier {
    let tip: HoverTip?
    @Environment(\.forcedHoverTipID) private var forced
    @State private var hovered = false
    @State private var pending: Task<Void, Never>?

    /// Long enough to cross a row of sprites without a tip flashing on each, short enough to feel immediate.
    static let delay = Duration.milliseconds(120)

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onHover { inside in
                pending?.cancel()
                guard inside else {
                    hovered = false
                    return
                }
                pending = Task {
                    try? await Task.sleep(for: Self.delay)
                    if !Task.isCancelled { hovered = true }
                }
            }
            .onDisappear {
                pending?.cancel()
                hovered = false
            }
            .transformAnchorPreference(key: HoverTipKey.self, value: .bounds) { items, anchor in
                guard let tip, hovered || forced == tip.id else { return }
                items.append(HoverTipItem(tip: tip, anchor: anchor))
            }
    }
}

/// Draws the hovered view's tip above it (below it near the top), kept inside the host's width. The host sits above
/// the scroll views and the cards, which clip what they hold.
@MainActor
private struct HoverTipHost: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(HoverTipKey.self) { items in
                GeometryReader { proxy in
                    // The innermost first: a view's own tip comes after those of the views it holds.
                    if let item = items.first {
                        let rect = proxy[item.anchor]
                        HoverTipLabel(title: item.tip.title)
                            .alignmentGuide(.leading) { d in
                                -min(max(rect.midX - d.width / 2, 6), max(6, proxy.size.width - d.width - 6))
                            }
                            .alignmentGuide(.top) { d in
                                let above = rect.minY - d.height - 4
                                return -(above >= 4 ? above : rect.maxY + 4)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .transition(.opacity)
                    }
                }
                .allowsHitTesting(false)
                .animation(.easeOut(duration: 0.1), value: items.first?.tip)
            }
            // A host inside another draws its own tips once.
            .transformPreference(HoverTipKey.self) { $0 = [] }
    }
}

/// The bubble: the text in a small translucent rounded box, on one line while it fits.
@MainActor
struct HoverTipLabel: View {
    let title: String

    /// Wider tips wrap: a forms goal names up to 27 forms.
    nonisolated static let maxWidth: CGFloat = 250

    var body: some View {
        Text(title).font(.caption.weight(.semibold))
            .frame(width: Self.width(of: title), alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.14)))
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
    }

    /// The text's width, measured: asked for its ideal size, a text answers one line and overflows the bubble once
    /// wrapped. Capped at `maxWidth`, where it wraps; a text with line breaks is as wide as its longest line.
    nonisolated static func width(of title: String) -> CGFloat {
        let font = NSFont.boldSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .caption1).pointSize)
        let longestLine = title.split(separator: "\n").map {
            (String($0) as NSString).size(withAttributes: [.font: font]).width
        }.max() ?? 0
        return min(longestLine.rounded(.up) + 2, maxWidth)
    }
}

extension View {
    /// Shows `tip` above this view on hover (`HoverTipSource`); nil shows nothing.
    func hoverTip(_ tip: HoverTip?) -> some View { modifier(HoverTipSource(tip: tip)) }

    /// Shows `text` above this view on hover; an empty or nil text shows nothing.
    func hoverTip(_ text: String?) -> some View {
        hoverTip(text.flatMap { $0.isEmpty ? nil : HoverTip(id: $0, title: $0) })
    }

    /// Draws the tips of the views it holds (`HoverTipHost`).
    func hoverTipHost() -> some View { modifier(HoverTipHost()) }
}

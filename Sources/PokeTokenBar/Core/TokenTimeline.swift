import Foundation

/// Tokens over the last week, minute by minute, oldest first: what a limit window's tokens are summed from
/// (`CandyWindow.windowTokens`). Minutes keep a five-hour window's start within a minute and the week small.
struct TokenTimeline: Sendable, Equatable {
    static let span = LimitWindowSpan.sevenDay

    /// Minutes since 1970, ascending, and the tokens of each.
    private(set) var minuteStarts: [Int] = []
    private(set) var minuteTokens: [Int] = []

    init(entries: some Sequence<LocalUsageReader.Entry>, now: Date) {
        let start = now.addingTimeInterval(-Self.span)
        var byMinute: [Int: Int] = [:]
        for entry in entries where entry.total > 0 && entry.date >= start && entry.date <= now {
            byMinute[Self.minute(entry.date), default: 0] += entry.total
        }
        for (minute, tokens) in byMinute.sorted(by: { $0.key < $1.key }) {
            minuteStarts.append(minute)
            minuteTokens.append(tokens)
        }
    }

    /// The tokens from `start` on.
    func tokens(since start: Date) -> Int {
        let first = Self.minute(start)
        var low = 0, high = minuteStarts.count
        while low < high {
            let middle = (low + high) / 2
            if minuteStarts[middle] < first { low = middle + 1 } else { high = middle }
        }
        return minuteTokens[low...].reduce(0, +)
    }

    /// The tokens of a limit window resetting at `reset` after `span`; nil without either.
    func windowTokens(reset: Date?, span: TimeInterval?) -> Int? {
        guard let reset, let span else { return nil }
        return tokens(since: reset.addingTimeInterval(-span))
    }

    private static func minute(_ date: Date) -> Int { Int((date.timeIntervalSince1970 / 60).rounded(.down)) }
}

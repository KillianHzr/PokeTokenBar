@testable import PokeTokenBar

extension CandyWindow {
    /// The same window with nothing used yet.
    var empty: CandyWindow {
        CandyWindow(key: key, name: name, kind: kind, utilization: 0, epoch: epoch, planMultiplier: planMultiplier)
    }
}

extension CompanionStore {
    /// Pays windows as a running app sees them fill: each one empty first, then as given. A window first seen at a
    /// level pays from that level on (#79), so a test that wants a window's candies shows it empty before.
    @MainActor
    func grantCandiesFilling(_ windows: [CandyWindow]) {
        grantCandies(from: windows.map(\.empty), limitsReady: true)
        grantCandies(from: windows, limitsReady: true)
    }
}

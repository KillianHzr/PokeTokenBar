import XCTest
@testable import PokeTokenBar

/// The first read waits, as a poll stuck on the network does; every later one answers at once.
private final class SlowFirstClaude: ClaudeLimitsProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var calls: Int { lock.withLock { count } }

    func fetch(allowKeychainPrompt: Bool) async throws -> LimitStatus {
        let call = lock.withLock { count += 1; return count }
        var status = LimitStatus()
        if call == 1 {
            try? await Task.sleep(nanoseconds: 400_000_000)
            status.accountEmail = "previous@example.com"
        } else {
            status.accountEmail = "current@example.com"
        }
        return status
    }
}
private struct NoCodex: CodexLimitsProviding {
    func fetch() async throws -> CodexRateLimitStatus? { nil }
}
private struct NoAntigravity: AntigravityLimitsProviding {
    func fetch(allowKeychainPrompt: Bool) async throws -> AntigravityRateLimitStatus {
        throw LimitsError.keychainInteractionNotAllowed
    }
}
private final class NoStatus: ProviderStatusProviding, @unchecked Sendable {
    func fetch() async -> [String: ProviderStatus] { [:] }
}

@MainActor
final class ClaudeLimitsReadOrderTests: XCTestCase {
    /// [Regression] A poll that waited on the network and answers after a newer manual refresh (after `/login` to
    /// another account) is left out: it overwrote the new account's limits with the previous one's, which fed the
    /// candies another account's windows.
    func testAnOlderPollDoesNotOverwriteANewerRead() async throws {
        let suite = "limits-order-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let claude = SlowFirstClaude()
        let store = UsageStore(providers: [], claudeLimitsProvider: claude, codexLimitsProvider: NoCodex(),
                               antigravityLimitsProvider: NoAntigravity(), statusProvider: NoStatus(),
                               autoRefresh: false, defaults: defaults)
        let poll = Task { await store.refresh(scheduleEmptyRetry: false) }
        for _ in 0..<200 where claude.calls < 1 { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(claude.calls, 1, "the poll is waiting on its read")

        await store.refreshLimitTokenFromKeychain()
        XCTAssertEqual(store.limits?.accountEmail, "current@example.com")
        await poll.value
        XCTAssertEqual(store.limits?.accountEmail, "current@example.com", "the older answer is left out")
    }
}

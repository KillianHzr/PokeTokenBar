import XCTest
@testable import PokeTokenBar

private struct NoNetwork: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { throw URLError(.notConnectedToInternet) }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { throw URLError(.notConnectedToInternet) }
}

/// What must never cost a save: a snapshot this build cannot read, a large one, a clock set ahead, an import, a file
/// that cannot be read, a save a later build wrote, a field of another shape.
@MainActor
final class SaveSafetyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func stateURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ptb-safety-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir.appendingPathComponent("companion-state.json")
    }

    private func state(dex: Int) -> CompanionState {
        var s = CompanionState()
        s.installBaselineSet = true
        s.usedSinceInstall = 5_000
        s.dex = (1...dex).map { DexEntry(baseID: $0, finalID: $0, chainOrder: [$0], rarity: .common, caughtAt: now) }
        return s
    }

    private func store(_ url: URL, writer: SaveWriter? = nil) -> CompanionStore {
        CompanionStore(provider: NoNetwork(), clock: { self.now }, fileURL: url, writer: writer)
    }

    /// [Regression] A snapshot of a later schema is left out and never restored as an empty game; the recovery of a
    /// broken save takes the next snapshot that reads.
    func testASnapshotThisBuildCannotReadIsNeverAnEmptyGame() throws {
        let url = try stateURL()
        let good = try SaveSnapshotManager.createSnapshot(state: state(dex: 3), for: url, date: now)
        let newer = SaveSnapshotManager.snapshotsDirectory(for: url)
            .appendingPathComponent(SaveSnapshotManager.snapshotFileName(date: now.addingTimeInterval(60)))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: good.fileURL)) as? [String: Any])
        object["schema"] = SaveEnvelope.schemaVersion + 1
        try JSONSerialization.data(withJSONObject: object).write(to: newer)

        XCTAssertEqual(SaveSnapshotManager.listSnapshots(for: url).map(\.dexCount), [3], "the later one is left out")
        XCTAssertThrowsError(try SaveSnapshotManager.loadEnvelope(from: newer)) {
            XCTAssertEqual($0 as? SaveTransferError, .newerSchema(found: SaveEnvelope.schemaVersion + 1,
                                                                  supported: SaveEnvelope.schemaVersion))
        }
        XCTAssertEqual(SaveSnapshotManager.loadLatestValidSnapshot(for: url)?.dex.count, 3)
    }

    /// [Regression] The app's own snapshots have no size limit (they grow by about 21 KB a day): past 8 MB one was
    /// refused, then read as a bare state, an empty game. They are written compact.
    func testALargeSnapshotStillRestoresAndIsCompact() throws {
        let url = try stateURL()
        var big = state(dex: 2)
        big.dex[0].names = [1: ["en": String(repeating: "x", count: SaveTransfer.maxFileBytes + 1_000)]]
        let snapshot = try SaveSnapshotManager.createSnapshot(state: big, for: url, date: now)
        let data = try Data(contentsOf: snapshot.fileURL)
        XCTAssertGreaterThan(data.count, SaveTransfer.maxFileBytes)
        XCTAssertFalse(String(decoding: data.prefix(200), as: UTF8.self).contains("\n "), "compact")
        XCTAssertEqual(try SaveSnapshotManager.loadEnvelope(from: snapshot.fileURL).state.dex.count, 2)
        XCTAssertEqual(SaveSnapshotManager.listSnapshots(for: url).first?.dexCount, 2)
        XCTAssertThrowsError(try SaveTransfer.decode(data), "a file picked by the player keeps its limit")
    }

    /// [Regression] A snapshot dated after now (the clock set ahead to try an event) no longer holds the automatic
    /// snapshots back until that date.
    func testAFutureSnapshotDoesNotHoldTheAutomaticOnesBack() throws {
        let url = try stateURL()
        try JSONEncoder().encode(state(dex: 2)).write(to: url)
        _ = try SaveSnapshotManager.createSnapshot(state: state(dex: 2), for: url, date: now.addingTimeInterval(30 * 86_400))
        let s = store(url)
        let before = s.availableSnapshots.count
        s.autoSnapshotIfNeeded(now: now)
        XCTAssertEqual(s.availableSnapshots.count, before + 1)
        s.autoSnapshotIfNeeded(now: now.addingTimeInterval(60))
        XCTAssertEqual(s.availableSnapshots.count, before + 1, "and the interval holds again")
    }

    /// [Regression] An import keeps the state it replaces as a snapshot, which Settings restores: the copy beside the
    /// save is a bare state the import refuses.
    func testAnImportKeepsTheReplacedStateAsASnapshot() throws {
        let url = try stateURL()
        try JSONEncoder().encode(state(dex: 4)).write(to: url)
        let s = store(url)
        let imported = try SaveTransfer.decode(SaveTransfer.encode(state: state(dex: 1), appVersion: "t", deviceName: "d",
                                                                   now: now))
        try s.applySave(imported, todayTokensByProvider: [:], todayDate: "2026-10-29", hasUsageData: false)
        XCTAssertEqual(s.state.dex.count, 1)
        let kept = try XCTUnwrap(s.availableSnapshots.first)
        XCTAssertEqual(kept.dexCount, 4, "the replaced state is a snapshot")
        try s.restoreSnapshot(kept)
        XCTAssertEqual(s.state.dex.count, 4)
    }

    /// [Regression] A save there but unreadable (permissions, a disk error) read as a new install and was written
    /// over: it locks the writes and says so.
    func testAnUnreadableSaveIsNotWrittenOver() throws {
        let url = try stateURL()
        let original = try JSONEncoder().encode(state(dex: 7))
        try original.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }
        let s = store(url)
        XCTAssertEqual(s.saveLock, .unreadable)
        s.update(todayTokensByProvider: ["claude_code": 10], todayDate: "2026-10-29", monthTotal: 10, burnTier: .idle,
                 limitWarning: false, hasUsageData: true)
        s.setLanguage(.fr)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        XCTAssertEqual(try Data(contentsOf: url), original, "nothing written")
        XCTAssertEqual(s.savesWritten, 0)
    }

    /// [Regression] Locked, the state is a fresh one: its automatic snapshots, every 12 hours, pushed the real ones out
    /// of the ten kept, and a restore took a snapshot before it was refused. No snapshot is written while locked.
    func testALockedSaveWritesNoSnapshot() throws {
        let url = try stateURL()
        try JSONEncoder().encode(state(dex: 7)).write(to: url)
        _ = try SaveSnapshotManager.createSnapshot(state: state(dex: 7), for: url, date: now.addingTimeInterval(-86_400))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }
        let s = store(url)
        XCTAssertEqual(s.saveLock, .unreadable)
        s.update(todayTokensByProvider: ["claude_code": 10], todayDate: "2026-10-29", monthTotal: 10, burnTier: .idle,
                 limitWarning: false, hasUsageData: true)
        s.autoSnapshotIfNeeded(now: now.addingTimeInterval(13 * 3600))
        XCTAssertThrowsError(try s.createManualSnapshot()) { XCTAssertEqual($0 as? SaveTransferError, .saveLocked) }
        let kept = try XCTUnwrap(s.availableSnapshots.first)
        XCTAssertThrowsError(try s.restoreSnapshot(kept)) { XCTAssertEqual($0 as? SaveTransferError, .saveLocked) }
        XCTAssertEqual(SaveSnapshotManager.listSnapshots(for: url).map(\.dexCount), [7], "only the real one")
    }

    /// [Regression] A save a later build wrote is not written over by this one, which would drop what it does not
    /// know. Written by an earlier build, it is, with this build stamped.
    func testASaveFromALaterBuildIsNotWrittenOver() throws {
        let url = try stateURL()
        var later = state(dex: 5)
        later.writer = SaveWriter(commit: "bbbbbbbcafe", date: "2026-12-01 10:00", time: 1_796_119_200)
        let original = try JSONEncoder().encode(later)
        try original.write(to: url)
        let mine = SaveWriter(commit: "aaaaaaa1234", date: "2026-10-29 10:00", time: 1_793_264_400)
        let s = store(url, writer: mine)
        XCTAssertEqual(s.saveLock, .newerBuild(commit: "bbbbbbb"))
        s.setLanguage(.de)
        XCTAssertEqual(try Data(contentsOf: url), original)

        var earlier = state(dex: 5)
        earlier.writer = SaveWriter(commit: "0000000beef", date: "2026-09-01 10:00", time: 1_788_249_600)
        try JSONEncoder().encode(earlier).write(to: url)
        let upgraded = store(url, writer: mine)
        XCTAssertNil(upgraded.saveLock)
        upgraded.setLanguage(.de)
        let saved = try JSONDecoder().decode(CompanionState.self, from: Data(contentsOf: url))
        XCTAssertEqual(saved.writer, mine, "this build stamps the save")
    }

    /// [Regression] Builds were ordered by their dates, each in its committer's time zone: a commit made in Seoul at
    /// 09:00 (00:00 UTC) read as later than one made after it in Paris at 08:30 (07:30 UTC), and locked the save of the
    /// later build. They are ordered by time; a save stamped before the time was, without one, is written.
    func testBuildsAreOrderedByTimeNotByTheirLocalDates() {
        let seoul = SaveWriter(commit: "1111111aaaa", date: "2026-10-30 09:00", time: 1_793_318_400)
        let paris = SaveWriter(commit: "2222222bbbb", date: "2026-10-30 08:30", time: 1_793_345_400)
        XCTAssertFalse(seoul.isNewer(than: paris), "Paris came later")
        XCTAssertTrue(paris.isNewer(than: seoul))
        let unstamped = SaveWriter(commit: "3333333cccc", date: "2026-12-31 23:59")
        XCTAssertFalse(unstamped.isNewer(than: paris), "no time to order by: written as before")
        XCTAssertFalse(paris.isNewer(than: unstamped))
    }

    /// [Regression] A field of another shape (a later build's, a broken one) falls back to its default: the file as
    /// it was is kept beside the save before the first write. A nature this build cannot read no longer drops the
    /// Pokémon raised.
    func testAFieldLeftOutKeepsTheOriginalAndTheActivePokemon() throws {
        let url = try stateURL()
        var s = state(dex: 2)
        s.active = MonState(baseID: 1, pathIDs: [1], stageIndex: 0, usedAtStage: 10, rarity: .common, totalForms: 1,
                            nature: .bold)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any])
        object["spentTokens"] = "a later shape"
        var active = try XCTUnwrap(object["active"] as? [String: Any])
        active["nature"] = "a nature of a later version"
        object["active"] = active
        let original = try JSONSerialization.data(withJSONObject: object)
        try original.write(to: url)

        let loaded = store(url)
        XCTAssertNotNil(loaded.state.active, "the Pokémon raised is kept")
        XCTAssertNil(loaded.state.active?.nature)
        let dir = url.deletingLastPathComponent()
        let copies = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix(CompanionStore.lossyCopyPrefix) }
        XCTAssertEqual(copies.count, 1)
        let copy = try XCTUnwrap(copies.first, "the original is kept beside the save")
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(copy)), original)

        let clean = try stateURL()
        try JSONEncoder().encode(state(dex: 2)).write(to: clean)
        _ = store(clean)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: clean.deletingLastPathComponent().path)
            .allSatisfy { !$0.hasPrefix(CompanionStore.lossyCopyPrefix) }, "a clean read keeps no copy")
    }
}

import XCTest
@testable import PokeTokenBar

/// A Claude transcript that grew is read from where the last read stopped: Claude Code only appends to it, and a
/// session of several hundred MB parsed whole at every refresh kept a core busy while it was being written.
/// Every fixture lives in a temporary folder.
final class ClaudeTranscriptResumeTests: XCTestCase {
    private var root: URL!
    private let fmt = LocalUsageReader.localDayFormatter()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ptb-transcript-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func turn(_ id: String, output: Int, cacheRead: Int = 100) -> String {
        """
        {"type":"assistant","requestId":"r-\(id)","timestamp":"2026-10-26T10:00:00.000Z","message":{"id":"m-\(id)","model":"claude-opus-4-8","usage":{"input_tokens":10,"output_tokens":\(output),"cache_creation_input_tokens":5,"cache_read_input_tokens":\(cacheRead)}}}
        """
    }

    private func ledger(_ cost: Double) -> String {
        "{\"type\":\"cost-state\",\"totalCostUSD\":\(cost),\"modelUsage\":{\"claude-opus-4-8\":{\"costUSD\":\(cost)}},\"hasUnknownModelCost\":false}"
    }

    private var file: URL { root.appendingPathComponent("session-1.jsonl") }

    private func write(_ text: String) throws { try text.write(to: file, atomically: true, encoding: .utf8) }

    private func append(_ text: String) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    private func read(after previous: LocalUsageReader.ClaudeTranscript? = nil) throws -> LocalUsageReader.ClaudeTranscript {
        try XCTUnwrap(LocalUsageReader.readClaudeTranscript(file, fmt: fmt, after: previous))
    }

    private func summary(_ entries: [LocalUsageReader.Entry]) -> [String] {
        entries.sorted { $0.id < $1.id }.map { "\($0.id) \($0.output) \($0.sessionID ?? "-")" }
    }

    /// Read in two steps or whole, the same turns, the same dedup and the newest cost ledger spread over every turn.
    func testAGrownTranscriptReadFromItsOffsetMatchesAWholeRead() throws {
        try write([turn("1", output: 10), turn("2", output: 20), ledger(1.0)].joined(separator: "\n") + "\n")
        let first = try read()
        try append([turn("2", output: 25), turn("3", output: 30), ledger(4.0)].joined(separator: "\n") + "\n")
        let resumed = try read(after: first)
        let whole = try read()

        XCTAssertEqual(resumed.offset, UInt64(try Data(contentsOf: file).count))
        XCTAssertEqual(summary(resumed.entries), summary(whole.entries))
        XCTAssertEqual(summary(resumed.entries), ["m-1|r-1 10 session-1", "m-2|r-2 25 session-1", "m-3|r-3 30 session-1"])
        XCTAssertEqual(resumed.costState, whole.costState)
        let cost = { (entries: [LocalUsageReader.Entry]) in entries.reduce(0) { $0 + ($1.explicitCost ?? 0) } }
        XCTAssertEqual(cost(resumed.entries), 4.0, accuracy: 1e-9, "the newest ledger covers the earlier turns too")
        for (a, b) in zip(resumed.entries.sorted { $0.id < $1.id }, whole.entries.sorted { $0.id < $1.id }) {
            XCTAssertEqual(a.explicitCost ?? -1, b.explicitCost ?? -1, accuracy: 1e-9, a.id)
        }

        // Grown again without a new ledger: the last one still spreads over every turn, as a whole read does.
        try append(turn("4", output: 40) + "\n")
        let again = try read(after: resumed)
        XCTAssertEqual(summary(again.entries), summary(try read().entries))
        XCTAssertEqual(cost(again.entries), 4.0, accuracy: 1e-9)
    }

    /// A last line without its line break counts if it is whole, and is read again once it ends, counted once.
    func testALineStillBeingWrittenIsReadAgainNextTime() throws {
        let cut = turn("2", output: 20)
        try write(turn("1", output: 10) + "\n" + cut.prefix(40))
        let first = try read()
        XCTAssertEqual(summary(first.entries), ["m-1|r-1 10 session-1"], "a cut line is not a turn yet")
        XCTAssertEqual(first.offset, UInt64(turn("1", output: 10).utf8.count + 1), "stops after the last line break")

        try append(String(cut.dropFirst(40)))
        let whole = try read(after: first)
        XCTAssertEqual(summary(whole.entries), ["m-1|r-1 10 session-1", "m-2|r-2 20 session-1"],
                       "a whole last line counts even before its line break")
        XCTAssertEqual(whole.offset, first.offset)

        try append("\n" + turn("3", output: 30) + "\n")
        XCTAssertEqual(summary(try read(after: whole).entries),
                       ["m-1|r-1 10 session-1", "m-2|r-2 20 session-1", "m-3|r-3 30 session-1"])
    }

    /// A file rewritten, shorter or with other bytes before the resume point, is read whole.
    func testARewrittenTranscriptIsReadWhole() throws {
        try write([turn("1", output: 10), turn("2", output: 20)].joined(separator: "\n") + "\n")
        let first = try read()

        // The bytes compared are the end of the line before the resume point.
        try write([turn("1", output: 10), turn("9", output: 90, cacheRead: 777), turn("3", output: 30)]
            .joined(separator: "\n") + "\n")
        XCTAssertEqual(summary(try read(after: first).entries),
                       ["m-1|r-1 10 session-1", "m-3|r-3 30 session-1", "m-9|r-9 90 session-1"])

        try write(turn("5", output: 50) + "\n")
        XCTAssertEqual(summary(try read(after: first).entries), ["m-5|r-5 50 session-1"], "shorter")
    }

    /// The cache hands each transcript its previous read: a turn whose bytes changed before the resume point, but
    /// outside the bytes compared, keeps its parsed value, which only a resumed read can give.
    func testTheCacheResumesAGrowingTranscript() async throws {
        let first = turn("1", output: 10)
        try write(first + "\n")
        let cache = LocalUsageCache(claudeRoot: root, fileURL: root.appendingPathComponent("cache.json"))
        let before = await cache.claudeEntries(modifiedSince: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(summary(before), ["m-1|r-1 10 session-1"])

        // Same length, an unreadable first turn, then a new line: a whole read would lose the first turn.
        try write(first.replacingOccurrences(of: "\"type\":\"assistant\"", with: "\"type\":\"xssistant\"") + "\n"
                  + turn("2", output: 20) + "\n")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: file.path)
        let after = await cache.claudeEntries(modifiedSince: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(summary(after), ["m-1|r-1 10 session-1", "m-2|r-2 20 session-1"])
    }
}

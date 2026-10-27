import XCTest
@testable import PokeTokenBar

/// A Claude transcript is read in chunks, so that the first read of a session of several hundred MB never holds the
/// whole file: a line cut by a chunk's end must read as if the file had been read at once.
final class ClaudeTranscriptChunkTests: XCTestCase {
    private var root: URL!
    private let fmt = LocalUsageReader.localDayFormatter()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ptb-chunks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func turn(_ id: String, output: Int) -> String {
        """
        {"type":"assistant","requestId":"r-\(id)","timestamp":"2026-10-26T10:00:00.000Z","message":{"id":"m-\(id)","model":"claude-opus-4-8","usage":{"input_tokens":10,"output_tokens":\(output),"cache_creation_input_tokens":5,"cache_read_input_tokens":100}}}
        """
    }

    private func ledger(_ cost: Double) -> String {
        "{\"type\":\"cost-state\",\"totalCostUSD\":\(cost),\"modelUsage\":{\"claude-opus-4-8\":{\"costUSD\":\(cost)}},\"hasUnknownModelCost\":false}"
    }

    private func summary(_ entries: [LocalUsageReader.Entry]) -> [String] {
        entries.sorted { $0.id < $1.id }.map { "\($0.id) \($0.output) \($0.sessionID ?? "-")" }
    }

    /// Every chunk size, down to a few bytes, reads the same turns, offset and ledger as one read of the whole file:
    /// a repeated turn kept once at its largest, the newest ledger, and a last line without its newline counted but
    /// left out of the offset.
    func testEveryChunkSizeReadsLikeTheWholeFile() throws {
        let file = root.appendingPathComponent("session-1.jsonl")
        let complete = [turn("1", output: 10), ledger(1.0), turn("2", output: 20), turn("2", output: 25), ledger(4.0)]
            .joined(separator: "\n") + "\n"
        try (complete + turn("3", output: 30)).write(to: file, atomically: true, encoding: .utf8)

        let whole = try XCTUnwrap(LocalUsageReader.parseClaudeFile(file, fromOffset: 0, fmt: fmt, chunkSize: 1 << 20))
        XCTAssertEqual(summary(whole.entries), ["m-1|r-1 10 session-1", "m-2|r-2 25 session-1", "m-3|r-3 30 session-1"])
        XCTAssertEqual(whole.newOffset, complete.utf8.count)
        XCTAssertEqual(whole.costState?.costByModel["claude-opus-4-8"], 4.0)

        for size in [1, 7, 64, 200, 333] {
            let read = try XCTUnwrap(LocalUsageReader.parseClaudeFile(file, fromOffset: 0, fmt: fmt, chunkSize: size))
            XCTAssertEqual(summary(read.entries), summary(whole.entries), "chunk \(size)")
            XCTAssertEqual(read.newOffset, whole.newOffset, "chunk \(size)")
            XCTAssertEqual(read.costState, whole.costState, "chunk \(size)")
        }
    }
}

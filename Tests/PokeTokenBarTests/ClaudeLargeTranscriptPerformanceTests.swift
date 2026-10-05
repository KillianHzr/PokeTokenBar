import Foundation
import XCTest
@testable import PokeTokenBar

/// A live Claude Code session is re-parsed whole on every refresh it changed in. A 252 MB session
/// took about 20 s with `String` split/contains, longer than the refresh interval, so refreshes chained
/// and kept one core at 100%. Opt-in like the Codex one: CI does not generate 256 MiB.
final class ClaudeLargeTranscriptPerformanceTests: XCTestCase {
    private let targetBytes = 256 * 1024 * 1024
    private let elapsedBudget: TimeInterval = 6
    private let rssGrowthBudgetBytes: UInt64 = 128 * 1024 * 1024

    func testClaudeLargeTranscriptParsesWithinRefreshBudget() throws {
        guard ProcessInfo.processInfo.environment["POKETOKENBAR_RUN_LARGE_PERF"] == "1" else {
            throw XCTSkip("Set POKETOKENBAR_RUN_LARGE_PERF=1 or run scripts/perf-codex-large-rollout.sh")
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-claude-large-\(UUID().uuidString)", isDirectory: true)
        let project = root.appendingPathComponent("-Users-someone-project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fixture = try writeLargeTranscript(to: project.appendingPathComponent("large-session.jsonl"))
        XCTAssertGreaterThanOrEqual(fixture.fileSize, targetBytes)

        let baselineRSS = PeakResidentSampler.currentResidentBytes()
        let sampler = PeakResidentSampler()
        sampler.start()
        let started = Date()
        let entries = LocalUsageReader.claudeEntries(modifiedSince: .distantPast, root: root)
        let elapsed = Date().timeIntervalSince(started)
        let peakRSS = sampler.stop()
        let rssGrowth = peakRSS >= baselineRSS ? peakRSS - baselineRSS : 0

        print(
            "PERF_RESULT claude size_mib=\(fixture.fileSize / 1024 / 1024) "
                + "rss_growth_mib=\(rssGrowth / 1024 / 1024) "
                + "elapsed_seconds=\(String(format: "%.3f", elapsed))"
        )

        XCTAssertEqual(entries.count, fixture.usageLines)
        XCTAssertEqual(entries.reduce(0) { $0 + $1.input }, fixture.expectedInput)
        XCTAssertEqual(entries.reduce(0) { $0 + $1.output }, fixture.expectedOutput)
        XCTAssertLessThan(elapsed, elapsedBudget, "256 MiB Claude transcript parse took \(elapsed)s")
        XCTAssertLessThan(rssGrowth, rssGrowthBudgetBytes,
                          "Parsing RSS growth \(rssGrowth / 1024 / 1024) MiB must not scale with the file")
    }

    private struct FixtureStats {
        let fileSize: Int
        let usageLines: Int
        let expectedInput: Int
        let expectedOutput: Int
    }

    /// Shaped like a real long session: large user/tool-result records with non-ASCII prose, and an
    /// assistant record carrying `usage` every few lines.
    private func writeLargeTranscript(to file: URL) throws -> FixtureStats {
        _ = FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }

        let prose = String(repeating: "Résumé : le déploiement a échoué, voilà pourquoi ça bloque. ", count: 140)
        let noise = #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"\#(prose)"}]},"timestamp":"2026-10-05T10:00:00.000Z"}"#
        let noiseData = Data((noise + "\n").utf8)

        var written = 0
        var usageLines = 0
        var expectedInput = 0
        var expectedOutput = 0
        while written < targetBytes {
            for _ in 0..<3 {
                handle.write(noiseData)
                written += noiseData.count
            }
            usageLines += 1
            let input = 10 + usageLines % 7, output = 100 + usageLines % 13
            expectedInput += input
            expectedOutput += output
            let line = #"{"type":"assistant","requestId":"req-\#(usageLines)","timestamp":"2026-10-05T10:00:00.000Z","message":{"id":"msg-\#(usageLines)","model":"claude-opus-5","content":[{"type":"text","text":"Très bien, je corrige ça."}],"usage":{"input_tokens":\#(input),"output_tokens":\#(output),"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}"#
            let data = Data((line + "\n").utf8)
            handle.write(data)
            written += data.count
        }
        return FixtureStats(fileSize: written, usageLines: usageLines,
                            expectedInput: expectedInput, expectedOutput: expectedOutput)
    }
}

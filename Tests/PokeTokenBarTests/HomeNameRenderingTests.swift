import AppKit
import SwiftUI
import Vision
import XCTest
@testable import PokeTokenBar

/// A line whose Pokémon has a name too long for one line beside the badge.
private struct LongNameProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []), rarity: .uncommon,
                names: [baseSpeciesID: ["en": "Charmander Charizard Blastoise"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// Home's card showed "Charmander Charizard B…" beside the rarity badge. The badge is above the name now, and the
/// name wraps whole.
@MainActor
final class HomeNameRenderingTests: XCTestCase {
    func testALongNameShowsWhole() async throws {
        let suite = "HomeName-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
        defer { try? FileManager.default.removeItem(at: file) }
        var state = CompanionState()
        state.language = .en
        state.installBaselineSet = true
        state.active = MonState(baseID: 128, pathIDs: [128], plannedPathIDs: [128], stageIndex: 0, usedAtStage: 0,
                                rarity: .uncommon, totalForms: 1, nature: .hardy)
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: LongNameProvider(), fileURL: file, defaults: defaults)
        store.update(todayTokensByProvider: [:], todayDate: "2026-10-23", monthTotal: 0, burnTier: .idle,
                     limitWarning: false, hasUsageData: true)
        for _ in 0..<300 where store.currentLine == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(store.displayName, "Charmander Charizard Blastoise")

        let width = PopoverMetrics.contentWidth
        let host = NSHostingView(rootView: CompanionHeader(store: store).frame(width: width)
            .background(Color.black).environment(\.colorScheme, .dark))
        host.frame = NSRect(origin: .zero, size: NSSize(width: width, height: 300))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: width, height: 300),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(300))
        host.layoutSubtreeIfNeeded()
        let bounds = host.bounds
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2),
            pixelsHigh: Int(bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = bounds.size
        host.cacheDisplay(in: bounds, to: bitmap)
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["en-US"]
        request.recognitionLevel = .accurate
        // Read on the CPU, as CI's runners do (no GPU there).
        if let cpu = try request.supportedComputeStageDevices[.main]?.first(where: {
            if case .cpu = $0 { return true } else { return false }
        }) {
            request.setComputeDevice(cpu, for: .main)
        }
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        for word in ["Charmander", "Charizard", "Blastoise", "UNCOMMON"] {
            XCTAssertTrue(text.contains(word), "\(word) missing from: \(text)")
        }
        XCTAssertFalse(text.contains("…"), "the name is cut: \(text)")
    }
}

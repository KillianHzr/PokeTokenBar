import AppKit
import XCTest
@testable import PokeTokenBar

/// What a draw or a refresh must not redo: the guards of the 2026-10-28 audit's interface findings.
@MainActor
final class UIWorkGuardTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    /// [Regression] The legendary badge draws 30 frames a second while its shine crosses, one where it ends, then none
    /// until the next cycle: its 30 fps timeline ran through the rest too.
    func testTheLegendaryShineRestsBetweenSweeps() {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_001)   // a cycle start: 800_000_001 = 3 × 266_666_667
        var date = start
        var frames = 0
        while date < start.addingTimeInterval(ShineSchedule.cycle) {
            date = ShineSchedule.next(after: date)
            frames += 1
        }
        XCTAssertLessThanOrEqual(frames, 47, "about 45 frames for the sweep, one at its end, one for the next cycle")
        XCTAssertGreaterThanOrEqual(frames, 44)
        XCTAssertEqual(ShineSchedule.phase(at: date), 0, accuracy: 0.001, "the next frame is the next cycle's start")
        var paused = ShineSchedule(paused: true).entries(from: start, mode: .normal)
        XCTAssertNotNil(paused.next())
        XCTAssertNil(paused.next(), "Reduce Motion: one frame")
    }

    /// [Regression] The rays turn by an animation, not by a timeline redrawing the whole card.
    func testTheLegendaryCardHasNoFullFrameRateTimeline() throws {
        let text = try source("Sources/PokeTokenBar/UI/DesignSystem.swift")
        XCTAssertFalse(text.contains("minimumInterval: 1.0 / 30"), "a 30 fps timeline redraws a whole view")
    }

    /// [Regression] The catch log reads the duplicate set once: each row sorted and walked the whole Pokédex for its
    /// own badge.
    func testCatchLogRowsDoNotRecomputeTheDuplicates() throws {
        let text = try source("Sources/PokeTokenBar/UI/CompanionView.swift")
        XCTAssertFalse(text.contains("store.isDuplicateCatch("))
    }

    /// [Regression] No SwiftUI `.popover` in the menu bar popover: it can outlive it as an orphan window.
    func testNoSwiftUIPopoverInsideThePopover() throws {
        for file in ["PopoverView.swift", "CompanionView.swift", "SettingsView.swift", "ShopView.swift", "BagView.swift",
                     "AchievementsView.swift", "StatsView.swift"] {
            let text = try source("Sources/PokeTokenBar/UI/\(file)")
            XCTAssertFalse(text.contains(".popover(isPresented:"), file)
        }
    }

    /// [Regression] The Stats page keeps no hover state: each bar entered recomputed the whole report.
    func testStatsHoverLivesInTheChart() throws {
        let text = try source("Sources/PokeTokenBar/UI/StatsView.swift")
        let page = text.components(separatedBy: "private struct StatsChart").first ?? text
        XCTAssertFalse(page.contains("@State private var hovered"))
        XCTAssertTrue(text.contains("private struct StatsChart"))
    }

    /// Answers every line with names, as PokéAPI does.
    private struct NamedLines: PokeProviding {
        func line(baseSpeciesID id: Int) async throws -> EvoLine {
            EvoLine(baseID: id, tree: EvoNode(speciesID: id, children: []), rarity: .common,
                    names: [id: ["en": "P\(id)", "ko": "포\(id)", "fr": "P\(id)"]])
        }
        func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
        func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    }

    private func store(provider: any PokeProviding = NamedLines(),
                       _ edit: (inout CompanionState) -> Void) throws -> CompanionStore {
        var state = CompanionState()
        state.installBaselineSet = true
        state.lastDate = "2026-10-29"
        edit(&state)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ui-guard-\(UUID().uuidString).json")
        try JSONEncoder().encode(state).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return CompanionStore(provider: provider, fileURL: url)
    }

    /// [Regression] A form species' page reads the Pokédex fold some 25 times per draw: it is kept until the state
    /// changes, and still follows that change.
    func testThePokedexFoldIsKeptUntilTheStateChanges() throws {
        let s = try store {
            $0.dex = [DexEntry(baseID: 201, finalID: 201, chainOrder: [201], rarity: .rare, caughtAt: nil,
                               form: PokemonForm("a")),
                      DexEntry(baseID: 1, finalID: 1, chainOrder: [1], rarity: .common, caughtAt: nil)]
        }
        let folds = s.dexSpeciesFolds
        for _ in 0..<25 {
            _ = s.formSpecies(speciesID: 201)
            _ = s.dexSpecies
        }
        XCTAssertEqual(s.dexSpeciesFolds - folds, 2, "once grouped by form, once not")
        XCTAssertEqual(s.formSpecies(speciesID: 201).map(\.form), [PokemonForm("a")])
        s.setLanguage(.fr)
        _ = s.dexSpecies
        XCTAssertEqual(s.dexSpeciesFolds - folds, 3, "a change of state folds again")
    }

    /// [Regression] A refresh with nothing new writes nothing observed: the day's ledger and the display state were
    /// assigned at each refresh, equal or not, which redrew every screen open.
    func testARefreshWithNothingNewTouchesNoObservedState() throws {
        let s = try store { _ in }
        func refresh() {
            s.update(todayTokensByProvider: ["claude_code": 1_000], todayDate: "2026-10-29", monthTotal: 1_000,
                     burnTier: .idle, limitWarning: false, hasUsageData: true)
        }
        refresh()
        refresh()
        final class Flag: @unchecked Sendable { var raised = false }
        let changed = Flag()
        withObservationTracking {
            _ = s.state
            _ = s.displayState
        } onChange: {
            changed.raised = true
        }
        refresh()
        XCTAssertFalse(changed.raised, "nothing new, nothing observed changed")
        s.update(todayTokensByProvider: ["claude_code": 2_000], todayDate: "2026-10-29", monthTotal: 2_000,
                 burnTier: .idle, limitWarning: false, hasUsageData: true)
        XCTAssertTrue(changed.raised, "new usage is a change")
    }

    /// [Regression] The name fill writes the save once: a names upgrade wrote it once per line of the Pokédex.
    func testTheNameFillSavesOnce() async throws {
        let s = try store {
            $0.dex = [1, 4, 7].map { DexEntry(baseID: $0, finalID: $0, chainOrder: [$0], rarity: .common, caughtAt: nil) }
        }
        let before = s.savesWritten
        await s.backfillMissingDexNames()
        XCTAssertEqual(s.savesWritten - before, 1)
    }

    /// The crop reads the alpha from one buffer, and gives what the per-pixel `colorAt` version gave: the content's
    /// square, centered on it, kept inside the canvas.
    func testCropToContentMatchesThePerPixelCrop() throws {
        func canvas(_ width: Int, _ height: Int, marks: [CGRect]) throws -> NSImage {
            let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            marks.forEach { context.fill($0) }
            let cg = try XCTUnwrap(context.makeImage())
            return NSImage(cgImage: cg, size: NSSize(width: width, height: height))
        }
        /// The previous crop, kept as the reference.
        func reference(_ image: NSImage) -> CGRect? {
            guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
            let w = rep.pixelsWide, h = rep.pixelsHigh
            var minX = w, minY = h, maxX = -1, maxY = -1
            for y in 0..<h {
                for x in 0..<w where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 {
                    if x < minX { minX = x }; if x > maxX { maxX = x }
                    if y < minY { minY = y }; if y > maxY { maxY = y }
                }
            }
            guard maxX >= minX, maxY >= minY else { return nil }
            let bw = maxX - minX + 1, bh = maxY - minY + 1
            let side = min(max(bw, bh), min(w, h))
            return CGRect(x: max(0, min(minX - (side - bw) / 2, w - side)),
                          y: max(0, min(minY - (side - bh) / 2, h - side)), width: side, height: side)
        }
        func pixels(_ image: NSImage) -> [UInt8] {
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
            var data = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
            data.withUnsafeMutableBytes { buffer in
                CGContext(data: buffer.baseAddress, width: cg.width, height: cg.height, bitsPerComponent: 8,
                          bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
                    .draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            }
            return data
        }
        for (width, height, marks) in [(10, 10, [CGRect(x: 6, y: 6, width: 2, height: 3)]),
                                       (96, 96, [CGRect(x: 30, y: 10, width: 28, height: 30)]),
                                       (40, 30, [CGRect(x: 0, y: 0, width: 3, height: 3), CGRect(x: 35, y: 25, width: 5, height: 5)])] {
            let image = try canvas(width, height, marks: marks)
            let expected = try XCTUnwrap(reference(image))
            let cropped = SpriteLoader.cropToContent(image)
            XCTAssertEqual(cropped.size, expected.size, "\(width)×\(height)")
            let cg = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil)?.cropping(to: expected))
            XCTAssertEqual(pixels(cropped), pixels(NSImage(cgImage: cg, size: expected.size)), "the same pixels")
        }
        let blank = try canvas(4, 4, marks: [])
        XCTAssertTrue(SpriteLoader.cropToContent(blank) === blank, "nothing drawn: the image as it is")
    }
}

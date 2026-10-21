import AppKit
import SwiftUI
import Vision
import XCTest
@testable import PokeTokenBar

private struct FormMetadataProvider: PokeProviding, PokemonDetailProviding {
    let detailsAvailable: Bool

    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []),
                rarity: .legendary, names: [baseSpeciesID: ["en": "Shaymin"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        guard detailsAvailable else { throw URLError(.notConnectedToInternet) }
        // PokéAPI's species data: default Shaymin types, stats and ability. The shown types follow the form.
        return PokemonDetails(speciesID: speciesID, name: "shaymin", height: 2, weight: 21,
            baseExperience: 270, genderRate: -1, types: ["grass"],
            baseStats: Dictionary(uniqueKeysWithValues: PokemonStatCalculator.order.map { ($0, 100) }),
            abilities: [PokemonAbilityOption(name: "natural-cure", slot: 1, isHidden: false)], moves: [])
    }
}

/// Reads the real Home and Pokédex pixels: a helper-only test would miss either missing call site.
@MainActor
final class FormMetadataNoteRenderingTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        windows.forEach { $0.close() }
        windows = []
    }

    private func store(form: PokemonForm?, speciesID: Int = 492, egg: Bool = false,
                       detailsAvailable: Bool = true) async throws -> CompanionStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("form-note-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("state.json")
        let suite = "FormMetadataNote-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        var state = CompanionState()
        state.language = .en
        if !egg {
            state.active = MonState(baseID: speciesID, pathIDs: [speciesID], stageIndex: 0,
                usedAtStage: 0, rarity: .legendary, totalForms: 1, form: form)
            let forms: [PokemonForm?] = speciesID == 492 ? [PokemonForm("land"), PokemonForm("sky")] : [nil]
            state.dex = forms.map {
                DexEntry(baseID: speciesID, finalID: speciesID, chainOrder: [speciesID], rarity: .legendary,
                         caughtAt: Date(timeIntervalSince1970: 1_700_000_000),
                         names: [speciesID: ["en": "Shaymin"]], form: $0)
            }
            state.representativeSpeciesID = speciesID
            state.representativeForm = form
        }
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: FormMetadataProvider(detailsAvailable: detailsAvailable),
                                   fileURL: file, defaults: defaults)
        if !egg && detailsAvailable { await store.loadPokemonDetails(speciesID: speciesID) }
        return store
    }

    private func mount<V: View>(_ view: V, height: CGFloat) -> NSView {
        let host = NSHostingView(rootView: view.frame(width: PopoverMetrics.contentWidth, height: height)
            .background(Color.white).environment(\.colorScheme, .light))
        host.frame = NSRect(x: 0, y: 0, width: PopoverMetrics.contentWidth, height: height)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000,
            width: host.frame.width, height: height), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.orderFront(nil)
        windows.append(window)
        return host
    }

    private func renderedText(_ host: NSView) throws -> String {
        host.layoutSubtreeIfNeeded()
        // Keep caption OCR at 2x regardless of the runner's screen backing scale.
        let bounds = host.bounds
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int((bounds.width * 2).rounded(.up)),
            pixelsHigh: Int((bounds.height * 2).rounded(.up)),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = bounds.size
        XCTAssertGreaterThanOrEqual(CGFloat(bitmap.pixelsWide) / bounds.width, 2)
        XCTAssertGreaterThanOrEqual(CGFloat(bitmap.pixelsHigh) / bounds.height, 2)
        host.cacheDisplay(in: bounds, to: bitmap)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ").lowercased()
    }

    /// The rendered text once `ready` holds, or after five seconds.
    private func renderedText(_ host: NSView, until ready: (String) -> Bool) async throws -> String {
        let deadline = ContinuousClock.now + .seconds(5)
        var text = ""
        repeat {
            text = try renderedText(host)
            if ready(text) { break }
            try await Task.sleep(for: .milliseconds(50))
        } while ContinuousClock.now < deadline
        return text
    }

    private func assertNote(_ expected: Bool, in host: NSView, loaded: Bool = true,
                            file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        var text = ""
        repeat {
            text = try renderedText(host)
            let ready = loaded ? text.contains("grass") : !text.isEmpty
            if ready && text.contains("data uses the default form") == expected { return }
            try await Task.sleep(for: .milliseconds(50))
        } while ContinuousClock.now < deadline
        XCTFail("Expected default-form note=\(expected). Rendered: \(text)", file: file, line: line)
    }

    /// Home shows the form's own types, with or without PokéAPI's data (which is the default form's: Grass for a
    /// Sky Shaymin), and no default-form note: nothing else on Home comes from that data.
    func testHomeShowsTheFormsOwnTypesWithoutTheNote() async throws {
        let cases: [(form: PokemonForm?, speciesID: Int, egg: Bool, loaded: Bool, shown: [String], hidden: [String])] = [
            (PokemonForm("sky"), 492, false, true, ["grass", "flying"], []),
            (PokemonForm("land"), 492, false, true, ["grass"], ["flying"]),
            (PokemonForm("sky"), 25, false, true, ["electric"], ["grass"]),
            (PokemonForm("sky"), 492, false, false, ["grass", "flying"], []),
            (nil, 492, true, false, [], ["grass"]),
        ]
        for item in cases {
            let store = try await store(form: item.form, speciesID: item.speciesID, egg: item.egg,
                                        detailsAvailable: item.loaded)
            let host = mount(CompanionHeader(store: store), height: 260)
            let text = try await renderedText(host) { !$0.isEmpty && item.shown.allSatisfy($0.contains) }
            for type in item.shown { XCTAssertTrue(text.contains(type), "\(type) in: \(text)") }
            for type in item.hidden { XCTAssertFalse(text.contains(type), "\(type) in: \(text)") }
            XCTAssertFalse(text.contains("data uses the default form"), text)
        }
    }

    /// The Pokédex shows the form's own types too, and keeps the note for the stats, size and abilities below them.
    func testDexExplainsTheDisplayedFormRatherThanTheOriginalSelection() async throws {
        for form in [PokemonForm("land"), PokemonForm("sky")] {
            let store = try await store(form: form)
            // Pass the aggregate/default species, as CollectionView does; the representative is Sky.
            let species = try XCTUnwrap(store.dexSpecies.first { $0.id == 492 })
            let host = mount(PokemonDetailView(store: store, species: species, onBack: {}), height: 520)
            try await assertNote(form == PokemonForm("sky"), in: host)
            // Type names load asynchronously: give Sky's second badge time to show its name.
            let text = try await renderedText(host) { form != PokemonForm("sky") || $0.contains("flying") }
            XCTAssertEqual(text.contains("flying"), form == PokemonForm("sky"), text)
        }
    }
}

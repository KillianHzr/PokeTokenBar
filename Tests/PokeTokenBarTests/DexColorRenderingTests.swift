import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import Vision
import XCTest
@testable import PokeTokenBar

private struct ColorRenderingProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class DexColorRenderingTests: XCTestCase {
    // Synthetic pixels make the two appearances unambiguous without network or user saves.
    private func solidImage(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 96, height: 96))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: 96, height: 96).fill()
        image.unlockFocus()
        return image
    }

    private func withSprites(_ body: () throws -> Void) throws {
        try withSprites([(606, false, nil, .red), (606, true, nil, .blue)], body)
    }

    /// These stills in the app's sprite cache while `body` runs.
    private func withSprites(_ sprites: [(id: Int, shiny: Bool, form: PokemonForm?, color: NSColor)],
                             _ body: () throws -> Void) throws {
        let keys = sprites.map {
            SpriteLoader.cacheDir.appendingPathComponent(
                SpriteStore.cacheKey(speciesID: $0.id, animated: false, shiny: $0.shiny, form: $0.form) + ".png").path as NSString
        }
        let previous = keys.map { SpriteLoader.imageCache.object(forKey: $0) }
        for (key, sprite) in zip(keys, sprites) {
            SpriteLoader.imageCache.setObject(solidImage(sprite.color), forKey: key)
        }
        defer {
            for (key, image) in zip(keys, previous) {
                if let image { SpriteLoader.imageCache.setObject(image, forKey: key) }
                else { SpriteLoader.imageCache.removeObject(forKey: key) }
            }
        }
        try body()
    }

    private func fixture(shinyLast: Bool) throws -> (CompanionStore, URL) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("dex-color-\(UUID()).json")
        var state = CompanionState()
        state.language = .en
        state.dex = [!shinyLast, shinyLast].enumerated().map { index, shiny in
            DexEntry(baseID: 606, finalID: 606, chainOrder: [606], rarity: .common,
                     caughtAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
                     isShiny: shiny, names: [606: ["en": "Elgyem"]])
        }
        try JSONEncoder().encode(state).write(to: file)
        return (CompanionStore(provider: ColorRenderingProvider(), fileURL: file), file)
    }

    private func fixture(onlyShiny: Bool) throws -> (CompanionStore, URL) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("dex-color-\(UUID()).json")
        var state = CompanionState()
        state.language = .en
        state.dex = [
            DexEntry(baseID: 606, finalID: 606, chainOrder: [606], rarity: .common,
                     caughtAt: Date(timeIntervalSince1970: 1_700_000_000),
                     isShiny: onlyShiny, names: [606: ["en": "Elgyem"]])
        ]
        try JSONEncoder().encode(state).write(to: file)
        return (CompanionStore(provider: ColorRenderingProvider(), fileURL: file), file)
    }

    private func colorRows(_ captured: NSBitmapImageRep, shiny: Bool) -> [Int] {
        // AppKit display caches may use float/extended color formats. Normalize via PNG
        // before reading components, matching the pixels written to the evidence file.
        guard let data = captured.representation(using: .png, properties: [:]),
              let bitmap = NSBitmapImageRep(data: data) else { return [] }
        var rows: [Int] = []
        for y in 0..<bitmap.pixelsHigh {
            var matches = 0
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.greenComponent < 0.4,
                   (shiny ? color.blueComponent > 0.8 && color.redComponent < 0.3
                          : color.redComponent > 0.8 && color.blueComponent < 0.3) {
                    matches += 1
                }
            }
            if matches >= 20 { rows.append(y) }
        }
        return rows
    }

    /// The selector's header updates synchronously, but SpriteView changes its cached image in
    /// .task(id:). Wait for those rendered pixels rather than assuming one 100ms sleep is enough.
    /// The deadline only bounds a broken test; the full pixel and badge assertions remain below.
    private func waitForDetailSprite(_ host: NSView, shiny: Bool) async throws -> NSBitmapImageRep {
        let deadline = ContinuousClock.now + .seconds(5)
        while true {
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let normalized = try XCTUnwrap(NSBitmapImageRep(data: png))
            let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
            // Center of the synthetic 82pt identity sprite, below the appearance picker.
            let pixel = try XCTUnwrap(normalized.colorAt(x: Int(41 * scale), y: Int(101 * scale))?
                .usingColorSpace(.deviceRGB))
            let ready = pixel.greenComponent < 0.4
                && (shiny ? pixel.blueComponent > 0.8 && pixel.redComponent < 0.3
                           : pixel.redComponent > 0.8 && pixel.blueComponent < 0.3)
            if ready || ContinuousClock.now >= deadline { return bitmap }
            // Yield the main actor so the appearance's .task and following SwiftUI render can run.
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Red normal and blue shiny Elgyem, still and animated, in a sprite folder of their own.
    private func spriteDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("detail-colors-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        for (shiny, color) in zip([false, true], [NSColor.red, NSColor.blue]) {
            let cgImage = try XCTUnwrap(solidImage(color).cgImage(forProposedRect: nil, context: nil, hints: nil))
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            let key = SpriteStore.cacheKey(speciesID: 606, animated: false, shiny: shiny)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent(key + ".png"))
            let data = NSMutableData()
            let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, cgImage, nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            let animatedKey = SpriteStore.cacheKey(speciesID: 606, animated: true, shiny: shiny)
            try (data as Data).write(to: directory.appendingPathComponent(animatedKey + ".gif"))
        }
        return directory
    }

    /// The Pokédex page of `store`'s Elgyem in a window, `selectedShiny` as the grid passes it.
    private func mountDetail(_ store: CompanionStore, selectedShiny: Bool?) throws -> (NSHostingView<AnyView>, NSWindow) {
        let species = try XCTUnwrap(store.dexSpecies.first)
        let view = PokemonDetailView(store: store, species: species, onBack: {}, selectedShiny: selectedShiny,
                                     spriteStore: SpriteStore(directory: try spriteDirectory()))
            .frame(width: PopoverMetrics.contentWidth, height: 520)
            .background(Color.white)
            .environment(\.colorScheme, .light)
        let host = NSHostingView(rootView: AnyView(view))
        host.frame = NSRect(x: 0, y: 0, width: PopoverMetrics.contentWidth, height: 520)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000,
            width: PopoverMetrics.contentWidth, height: 520), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.orderFront(nil)
        return (host, window)
    }

    /// A shiny Elgyem, then a normal one: the page opened on the latest catch, in normal colors. It opens shiny.
    func testDetailOpensShinyWhenTheLatestCatchIsNormal() async throws {
        let (store, file) = try fixture(shinyLast: false)
        defer { try? FileManager.default.removeItem(at: file) }
        let (host, window) = try mountDetail(store, selectedShiny: nil)
        defer { window.close() }
        let bitmap = try await waitForDetailSprite(host, shiny: true)
        XCTAssertGreaterThan(colorRows(bitmap, shiny: true).count, 40, "the page must open on the shiny sprite")
        XCTAssertEqual(colorRows(bitmap, shiny: false).count, 0, "no normal sprite on a page that opens shiny")
        // The identity hero card says Shiny: the picker and the page agree.
        let scale = CGFloat(bitmap.pixelsWide) / PopoverMetrics.contentWidth
        let header = try XCTUnwrap(bitmap.cgImage?.cropping(to:
            CGRect(x: 110 * scale, y: 60 * scale, width: 210 * scale, height: 140 * scale)))
        let recognition = VNRecognizeTextRequest()
        recognition.recognitionLevel = .accurate
        recognition.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: header).perform([recognition])
        let text = recognition.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ") ?? ""
        XCTAssertTrue(text.contains("Shiny"), "the page opens on the shiny individual: \(text)")
    }

    /// Caught shiny only: the picker still shows, and Normal shows the normal look as a preview. It used to need both
    /// looks caught, so a form caught shiny only had no way to its usual colors.
    func testAPokemonCaughtShinyOnlyStillShowsItsNormalLook() async throws {
        let (store, file) = try fixture(onlyShiny: true)
        defer { try? FileManager.default.removeItem(at: file) }
        let (host, window) = try mountDetail(store, selectedShiny: false)
        defer { window.close() }
        let bitmap = try await waitForDetailSprite(host, shiny: false)
        XCTAssertGreaterThan(colorRows(bitmap, shiny: false).count, 40, "Normal picked: the normal look")
        XCTAssertEqual(colorRows(bitmap, shiny: true).count, 0)
        // The picker itself shows: picking Normal by code alone would pass with it hidden.
        let recognition = VNRecognizeTextRequest()
        recognition.recognitionLevel = .accurate
        recognition.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: try XCTUnwrap(bitmap.cgImage)).perform([recognition])
        let words = (recognition.results ?? []).flatMap { $0.topCandidates(3).map(\.string) }
        XCTAssertTrue(words.contains { $0.contains(store.l.dexNormalLabel) }, "the Normal/Shiny picker: \(words)")
    }

    func testDetailSelectorChangesMountedPixelsAndReturnsToNormal() async throws {
        let (store, file) = try fixture(shinyLast: true)
        defer { try? FileManager.default.removeItem(at: file) }
        let (host, window) = try mountDetail(store, selectedShiny: false)
        defer { window.close() }
        /// Clicks the appearance picker's segment: it is the first row of the page under the Back row (the species has no
        /// forms), Normal on the left half, Shiny on the right.
        var eventNumber = 0
        func click(shiny: Bool) async throws {
            // Low on the left half: where the hero card's glow, which reaches up past the card, used to take the click.
            let point = NSPoint(x: PopoverMetrics.contentWidth * (shiny ? 0.72 : 0.22), y: 520 - 45)
            // Moved first: SwiftUI follows the pointer, and a press away from where it last saw it is dropped.
            for type in [NSEvent.EventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
                try await Task.sleep(for: .milliseconds(40))
                eventNumber += 1
                // Distinct timestamps and numbers: identical events are not taken as a new click.
                if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                                  timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: window.windowNumber, context: nil, eventNumber: eventNumber,
                                                  clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) {
                    window.sendEvent(event)
                }
            }
        }
        for (step, shiny) in [false, true, false].enumerated() {
            host.layoutSubtreeIfNeeded()
            try await click(shiny: shiny)
            let bitmap = try await waitForDetailSprite(host, shiny: shiny)
            XCTAssertGreaterThan(colorRows(bitmap, shiny: shiny).count, 40,
                                 "step \(step): selected \(shiny ? "shiny" : "normal") sprite must appear within 5 seconds")
            XCTAssertEqual(colorRows(bitmap, shiny: !shiny).count, 0,
                           "step \(step): selected \(shiny ? "shiny" : "normal") must not retain the previous appearance")
            let scale = CGFloat(bitmap.pixelsWide) / PopoverMetrics.contentWidth
            // The identity hero card under the appearance picker: name, types and the Shiny line.
            let header = try XCTUnwrap(bitmap.cgImage?.cropping(to:
                CGRect(x: 110 * scale, y: 60 * scale, width: 210 * scale, height: 140 * scale)))
            let recognition = VNRecognizeTextRequest()
            recognition.recognitionLevel = .accurate
            recognition.recognitionLanguages = ["en-US"]
            try VNImageRequestHandler(cgImage: header).perform([recognition])
            let text = recognition.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ") ?? ""
            XCTAssertTrue(text.contains("Elgyem"), "header crop must contain the rendered identity: \(text)")
            XCTAssertEqual(text.contains("Shiny"), shiny, "badge must follow the displayed individual: \(text)")
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to:
                URL(fileURLWithPath: "/private/tmp/dex-color-detail-\(shiny ? "shiny" : "normal").png"))
        }
    }

    func testCatchLogRendersEachIndividualsColorInBothAcquisitionOrdersAndOnReentry() throws {
        try withSprites {
            for shinyLast in [false, true] {
                let (store, file) = try fixture(shinyLast: shinyLast)
                defer { try? FileManager.default.removeItem(at: file) }
                for visit in 0..<2 {
                    let navigation = PopoverNavigation()
                    navigation.showingCollectionLog = true
                    let view = CollectionView(store: store, navigation: navigation)
                        .frame(width: PopoverMetrics.contentWidth, height: 520)
                        .background(Color.white)
                        .environment(\.colorScheme, .light)
                        .environment(\.locale, store.language.displayLocale)
                    let host = NSHostingView(rootView: view)
                    host.frame = NSRect(x: 0, y: 0, width: PopoverMetrics.contentWidth, height: 520)
                    let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000,
                        width: PopoverMetrics.contentWidth, height: 520),
                        styleMask: .borderless, backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.appearance = NSAppearance(named: .aqua)
                    window.contentView = host
                    window.orderFront(nil)
                    defer { window.close() }
                    host.layoutSubtreeIfNeeded()
                    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
                    host.layoutSubtreeIfNeeded()
                    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to:
                        URL(fileURLWithPath: "/private/tmp/dex-color-log-shiny-last-\(shinyLast).png"))
                    let normalRows = colorRows(bitmap, shiny: false)
                    let shinyRows = colorRows(bitmap, shiny: true)
                    XCTAssertGreaterThan(normalRows.count, 20, "normal catch must retain normal pixels")
                    XCTAssertGreaterThan(shinyRows.count, 20, "shiny catch must retain shiny pixels")
                    let firstNormal = try XCTUnwrap(normalRows.first)
                    let firstShiny = try XCTUnwrap(shinyRows.first)
                    XCTAssertEqual(firstShiny < firstNormal, shinyLast, "newest catch is first; colors must follow its individual")
                    if visit == 0 {
                        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to:
                            URL(fileURLWithPath: "/private/tmp/dex-color-log-shiny-last-\(shinyLast).png"))
                    }
                }
            }
        }
    }

    func testPokedexGridRendersShinySpeciesColor() throws {
        try withSprites {
            for shiny in [true, false] {
                let (store, file) = try fixture(onlyShiny: shiny)
                defer { try? FileManager.default.removeItem(at: file) }
                let navigation = PopoverNavigation()
                navigation.dexScope = .caught   // the caught species page by page
                navigation.showingCollectionLog = false
                let view = CollectionView(store: store, navigation: navigation)
                    .frame(width: PopoverMetrics.contentWidth, height: 520)
                    .background(Color.white)
                    .environment(\.colorScheme, .light)
                    .environment(\.locale, store.language.displayLocale)
                let host = NSHostingView(rootView: view)
                host.frame = NSRect(x: 0, y: 0, width: PopoverMetrics.contentWidth, height: 520)
                let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000,
                    width: PopoverMetrics.contentWidth, height: 520),
                    styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: .aqua)
                window.contentView = host
                window.orderFront(nil)
                defer { window.close() }
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
                host.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let normalRows = colorRows(bitmap, shiny: false)
                let shinyRows = colorRows(bitmap, shiny: true)
                if shiny {
                    XCTAssertGreaterThan(shinyRows.count, 20, "shiny species must render shiny pixels in Pokédex grid")
                    XCTAssertEqual(normalRows.count, 0, "shiny species must not render normal pixels in Pokédex grid")
                } else {
                    XCTAssertGreaterThan(normalRows.count, 20, "normal species must render normal pixels in Pokédex grid")
                    XCTAssertEqual(shinyRows.count, 0, "normal species must not render shiny pixels in Pokédex grid")
                }
            }
        }
    }

    /// A shiny Alolan Vulpix, then a normal Kanto one: the cell of a species with forms always showed its default
    /// form in normal colors. It shows the Pokémon its page opens on, the shiny Alolan Vulpix.
    func testPokedexGridShowsTheShinyFormOfASpeciesWithForms() throws {
        let kanto = PokemonForm("normal"), alola = PokemonForm("alola")
        try withSprites([(37, false, kanto, .red), (37, true, alola, .blue)]) {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("dex-color-\(UUID()).json")
            defer { try? FileManager.default.removeItem(at: file) }
            var state = CompanionState()
            state.language = .en
            state.dex = [(alola, true), (kanto, false)].enumerated().map { index, item in
                DexEntry(baseID: 37, finalID: 37, chainOrder: [37], rarity: .common,
                         caughtAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
                         isShiny: item.1, names: [37: ["en": "Vulpix"]], form: item.0)
            }
            try JSONEncoder().encode(state).write(to: file)
            let store = CompanionStore(provider: ColorRenderingProvider(), fileURL: file)
            let caught = PopoverNavigation()
            caught.dexScope = .caught   // the caught species page by page
            let view = CollectionView(store: store, navigation: caught)
                .frame(width: PopoverMetrics.contentWidth, height: 520)
                .background(Color.white)
                .environment(\.colorScheme, .light)
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(x: 0, y: 0, width: PopoverMetrics.contentWidth, height: 520)
            let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: PopoverMetrics.contentWidth, height: 520),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = host
            window.orderFront(nil)
            defer { window.close() }
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            XCTAssertGreaterThan(colorRows(bitmap, shiny: true).count, 20, "the shiny Alolan Vulpix in the cell")
            XCTAssertEqual(colorRows(bitmap, shiny: false).count, 0, "not the normal Kanto Vulpix")
        }
    }
}


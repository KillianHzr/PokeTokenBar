import AppKit
import SwiftUI
import Vision
import XCTest
@testable import PokeTokenBar

/// The app's tooltips (`HoverTip`): drawn by the popover above its cards, at once, over every view that has one. The
/// system's tooltip waited about a second and never showed over the faded sprites of the Pokémon still missing.
@MainActor
final class HoverTipTests: XCTestCase {
    private func render(_ view: some View, width: CGFloat = 320, height: CGFloat = 160) async throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view.frame(width: width, height: height, alignment: .topLeading)
            .background(Color.white).environment(\.colorScheme, .light))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: width, height: height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(300))
        host.layoutSubtreeIfNeeded()
        // Twice the points, as on a Retina screen: at 1x (the CI's) the text recognition drops letters.
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * 2),
            pixelsHigh: Int(height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = host.bounds.size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    private func words(_ bitmap: NSBitmapImageRep) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: try XCTUnwrap(bitmap.cgImage)).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }

    /// The hovered view's tip shows, and only its own; a view outside a host shows none.
    func testTheHostDrawsTheHoveredViewsTip() async throws {
        func row(forcing id: String?) -> some View {
            HStack(spacing: 40) {
                Color.gray.frame(width: 30, height: 30).hoverTip("Charmander")
                Color.gray.frame(width: 30, height: 30).hoverTip("Squirtle")
            }
            .padding(.top, 80).padding(.leading, 60)
            // A card with its own tip around them keeps theirs.
            .hoverTip("Card")
            .environment(\.forcedHoverTipID, id)
        }
        let hovered = try words(try await render(row(forcing: "Squirtle").hoverTipHost()))
        XCTAssertTrue(hovered.contains("Squirtle"), hovered)
        XCTAssertFalse(hovered.contains("Charmander"), hovered)
        let none = try words(try await render(row(forcing: nil).hoverTipHost()))
        XCTAssertFalse(none.contains("Squirtle"), "nothing hovered")
        let hostless = try words(try await render(row(forcing: "Squirtle")))
        XCTAssertFalse(hostless.contains("Squirtle"), "no host, no tip")
    }

    /// A long tip wraps inside its bubble rather than running past it, and stays inside the host's width.
    func testALongTipWrapsWithinItsBubbleAndTheHost() async throws {
        let long = "Still missing: Icy Snow, Tundra, Continental, Elegant, Modern, Marine, Archipelago, High Plains"
        XCTAssertEqual(HoverTipLabel.width(of: long), HoverTipLabel.maxWidth)
        XCTAssertLessThan(HoverTipLabel.width(of: "Pikachu"), 80)
        let bitmap = try await render(
            Color.gray.frame(width: 30, height: 30).hoverTip(long)
                .padding(.top, 120).padding(.leading, 4)
                .environment(\.forcedHoverTipID, long)
                .hoverTipHost(), height: 200)
        let text = try words(bitmap)
        // Words inside the lines: the first of a line touches the bubble's edge, where recognition is least sure.
        for word in ["missing", "Tundra", "Modern", "Archipelago", "Plains"] {
            XCTAssertTrue(text.contains(word), "\(word) in \(text)")
        }
    }

    /// The Pokémon named on hover in the achievements, the Stats page and the digs: the missing ones too.
    func testAPokemonsTipNamesItEvenMissing() async throws {
        let names = PokemonNameDisplayStore()
        _ = await names.load(.init(kind: .pokemonSpecies, name: "4"), provider: StaticNames(names: ["en": "Charmander"]))
        let tip = Color.clear.frame(width: 30, height: 30)
            .modifier(SpeciesNameTooltip(speciesID: 4, language: .en, displayStore: names,
                                         provider: StaticNames(names: ["en": "Charmander"])))
            .padding(.top, 80).padding(.leading, 60)
            .environment(\.forcedHoverTipID, "species:4:")
            .hoverTipHost()
        let text = try words(try await render(tip))
        XCTAssertTrue(text.contains("Charmander"), text)
    }

    /// Every tooltip of the app is a `HoverTip`: a system one (`.help`) would wait a second again, and never show
    /// over a faded view.
    func testTheAppHasNoSystemTooltip() throws {
        let ui = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeTokenBar/UI")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: ui, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() {
                let code = line.components(separatedBy: "//").first ?? ""
                if code.contains(".help(") || code.contains(" help(") { offenders.append("\(url.lastPathComponent):\(index + 1)") }
            }
        }
        XCTAssertTrue(offenders.isEmpty, "use .hoverTip: \(offenders.joined(separator: ", "))")
    }
}

private struct StaticNames: PokemonNameProviding {
    let names: [String: String]
    func names(for resource: PokemonNameResource) async throws -> [String: String] { names }
}

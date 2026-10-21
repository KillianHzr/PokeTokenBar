import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import PokeTokenBar

/// A Pokémon's still is the first frame of its 3D animation. Stills used to be PokeAPI's pixel PNGs, so a Pokémon
/// switched from pixel art to a 3D render when it started moving (in the collection, on Home, in the menu bar).
final class SpriteStillTests: XCTestCase {
    private func directory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sprite-stills-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func pixels(red: CGFloat, green: CGFloat) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: red, green: green, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        return try XCTUnwrap(context.makeImage())
    }

    /// A two-frame GIF: red, then green.
    private func gif() throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 2, nil))
        for (red, green) in [(CGFloat(1), CGFloat(0)), (CGFloat(0), CGFloat(1))] {
            CGImageDestinationAddImage(destination, try pixels(red: red, green: green),
                                       [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func redness(_ png: Data) throws -> (red: CGFloat, green: CGFloat) {
        let color = try XCTUnwrap(NSBitmapImageRep(data: png)?.colorAt(x: 1, y: 1)?.usingColorSpace(.deviceRGB))
        return (color.redComponent, color.greenComponent)
    }

    /// The still comes from the cached animation, with no download, and is cached as the still.
    func testAStillIsTheFirstFrameOfTheAnimation() async throws {
        let dir = try directory()
        try gif().write(to: dir.appendingPathComponent("6-a.gif"))
        try gif().write(to: dir.appendingPathComponent("37-alola-sha.gif"))
        let store = SpriteStore(directory: dir)

        let loaded = await store.data(speciesID: 6, animated: false)
        let still = try XCTUnwrap(loaded)
        let color = try redness(still)
        XCTAssertGreaterThan(color.red, color.green + 0.5, "the first frame, red, not the second, green")
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("6-s.png")), still)

        let loadedShiny = await store.data(speciesID: 37, animated: false, shiny: true, form: PokemonForm("alola"))
        let shinyForm = try XCTUnwrap(loadedShiny)
        let shinyColor = try redness(shinyForm)
        XCTAssertGreaterThan(shinyColor.red, shinyColor.green + 0.5)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("37-alola-shs.png").path))
    }

    /// Pixel stills cached by earlier versions are deleted once; animations, items and the egg stay, and a still
    /// made after the purge is kept.
    func testCachedPixelStillsArePurgedOnce() throws {
        let dir = try directory()
        let files = ["6-s.png", "6-shs.png", "201-b-s.png", "37-alola-shs.png", "1025-s.png",
                     "6-a.gif", "item-oval-charm.png", "egg.png"]
        for name in files { FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data([1])) }
        SpriteStore.purgePixelStills(in: dir)
        let left = Set(try FileManager.default.contentsOfDirectory(atPath: dir.path)).subtracting([".showdown-stills-v1"])
        XCTAssertEqual(left, ["6-a.gif", "item-oval-charm.png", "egg.png"])
        FileManager.default.createFile(atPath: dir.appendingPathComponent("6-s.png").path, contents: Data([2]))
        SpriteStore.purgePixelStills(in: dir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("6-s.png").path))
    }
}

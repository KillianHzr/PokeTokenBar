import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// The catch log and a Pokémon's page stand their Pokémon on the bottom of the box: each sprite moves down by the
/// transparent margin under it, which differs from one image to the next.
@MainActor
final class SpriteGroundTests: XCTestCase {
    /// A 10×20 canvas with an opaque block on rows `top..<bottom` counted from the top.
    private static func sprite(top: Int, bottom: Int, alpha: CGFloat = 1, color: NSColor = .red) -> NSImage {
        let image = NSImage(size: NSSize(width: 10, height: 20), flipped: true) { _ in
            color.withAlphaComponent(alpha).setFill()
            NSRect(x: 2, y: top, width: 6, height: bottom - top).fill()
            return true
        }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 10, pixelsHigh: 20, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: 10, height: 20))
        NSGraphicsContext.restoreGraphicsState()
        let pixels = NSImage(size: NSSize(width: 10, height: 20))
        pixels.addRepresentation(rep)
        return pixels
    }

    func testTheMarginIsTheEmptyRowsUnderThePokemon() {
        XCTAssertEqual(SpriteFit.bottomMargin(of: Self.sprite(top: 2, bottom: 15)), 5.0 / 20, accuracy: 0.0001)
        XCTAssertEqual(SpriteFit.bottomMargin(of: Self.sprite(top: 0, bottom: 20)), 0, "already on the ground")
        XCTAssertEqual(SpriteFit.bottomMargin(of: Self.sprite(top: 4, bottom: 12, alpha: 0.05)), 0,
                       "nothing visible: no margin rather than a fall")
        XCTAssertEqual(SpriteFit.bottomMargin(of: NSImage(size: .zero)), 0, "an unreadable image stays put")
    }

    /// Rendered: two sprites whose images leave 10 and 2 empty rows under them stand on the same bottom line when
    /// grounded, and keep their centred places otherwise.
    func testGroundedSpritesShareTheirBottomLine() throws {
        // Files in a store of its own: a sprite the view had to fetch would land in the shared cache during a later
        // test (docs/reference/defect-log.md).
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ground-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for (id, margin) in [(4, 10), (6, 2)] {
            let image = Self.sprite(top: 2, bottom: 20 - margin, color: .green)
            let png = try XCTUnwrap((image.representations.first as? NSBitmapImageRep)?.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("\(SpriteStore.cacheKey(speciesID: id, animated: false, shiny: false)).png"))
        }
        let store = SpriteStore(directory: directory)
        func bottoms(grounded: Bool) throws -> [Int] {
            let row = HStack(spacing: 10) {
                SpriteView(speciesID: 4, size: 40, spriteStore: store, bottomAligned: grounded)
                SpriteView(speciesID: 6, size: 40, spriteStore: store, bottomAligned: grounded)
            }
            .background(Color.white)
            let host = NSHostingView(rootView: row)
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let half = bitmap.pixelsWide / 2
            return [0..<half, half..<bitmap.pixelsWide].map { columns in
                (0..<bitmap.pixelsHigh).last { y in
                    columns.contains { x in
                        guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
                        return c.greenComponent > 0.8 && c.redComponent < 0.3 && c.blueComponent < 0.3
                    }
                } ?? -1
            }
        }
        let grounded = try bottoms(grounded: true)
        XCTAssertEqual(grounded[0], grounded[1], "one ground line: \(grounded)")
        let centred = try bottoms(grounded: false)
        XCTAssertNotEqual(centred[0], centred[1], "not grounded, each keeps its image's place: \(centred)")
    }
}

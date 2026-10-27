import AppKit
import XCTest
@testable import PokeTokenBar

/// The catch log and a Pokémon's page stand their Pokémon on the bottom of the box: each sprite moves down by the
/// transparent margin under it, which differs from one image to the next.
@MainActor
final class SpriteGroundTests: XCTestCase {
    /// A 10×20 canvas with an opaque block on rows `top..<bottom` counted from the top.
    private static func sprite(top: Int, bottom: Int, alpha: CGFloat = 1) -> NSImage {
        let image = NSImage(size: NSSize(width: 10, height: 20), flipped: true) { _ in
            NSColor.red.withAlphaComponent(alpha).setFill()
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
}

import AppKit
import XCTest
@testable import PokeTokenBar

/// Green and orange text read on the popover's cards in both appearances: at least 4.5:1, the contrast small text
/// needs. The system's green and orange are under 2.5:1 on a light card.
final class ReadableColorTests: XCTestCase {
    private func luminance(_ color: NSColor, in name: NSAppearance.Name) throws -> Double {
        var resolved: NSColor?
        try XCTUnwrap(NSAppearance(named: name)).performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB)
        }
        let c = try XCTUnwrap(resolved)
        func linear(_ v: CGFloat) -> Double {
            let v = Double(v)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent) + 0.0722 * linear(c.blueComponent)
    }

    private func contrast(_ a: Double, _ b: Double) -> Double { (max(a, b) + 0.05) / (min(a, b) + 0.05) }

    func testGreenAndOrangeTextReadOnLightAndDarkCards() throws {
        let lightCard = 0.85, darkCard = 0.03   // a card's luminance: about 93% and 18% gray
        for color in [NSColor.readableGreen, NSColor.readableOrange] {
            XCTAssertGreaterThanOrEqual(contrast(try luminance(color, in: .aqua), lightCard), 4.5, "\(color) on light")
            XCTAssertGreaterThanOrEqual(contrast(try luminance(color, in: .darkAqua), darkCard), 4.5, "\(color) on dark")
        }
        // The control: the system green on a light card.
        XCTAssertLessThan(contrast(try luminance(.systemGreen, in: .aqua), lightCard), 3)
    }
}

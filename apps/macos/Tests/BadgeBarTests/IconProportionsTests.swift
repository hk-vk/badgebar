import AppKit
import XCTest
@testable import BadgeBar

/// Icons must keep their own proportions in the menu bar, whatever shape they are.
final class IconProportionsTests: XCTestCase {
    /// A filled rectangle with a transparent margin, like an imported image.
    private func image(width: CGFloat, height: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            NSColor.systemBlue.setFill()
            rect.insetBy(dx: width * 0.1, dy: height * 0.1).fill()
            return true
        }
    }

    /// Width over height of what's visible in an image, drawn without changing its shape.
    private func visibleRatio(of image: NSImage) -> CGFloat {
        let scale = 160 / max(image.size.width, image.size.height)
        let width = Int(image.size.width * scale), height = Int(image.size.height * scale)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()

        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where rep.bitmapData![(y * width + x) * 4 + 3] > 128 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        return CGFloat(maxX - minX + 1) / CGFloat(maxY - minY + 1)
    }

    private func menuBarImage(_ icon: NSImage) -> NSImage {
        var appearance = BadgeAppearance()
        appearance.emptyBehavior = .show
        return BadgeRenderer.image(icon: icon, badge: nil, appearance: appearance)
    }

    func testSymbolsKeepTheirProportions() throws {
        for name in ["envelope.fill", "briefcase.fill", "rectangle.fill"] {
            let symbol = try XCTUnwrap(NSImage(systemSymbolName: name, accessibilityDescription: nil))
            symbol.isTemplate = true
            XCTAssertEqual(visibleRatio(of: menuBarImage(symbol)), visibleRatio(of: symbol), accuracy: 0.12, name)
        }
    }

    func testImagesKeepTheirProportions() {
        for (width, height, ratio) in [(200.0, 100.0, 2.0), (100.0, 200.0, 0.5), (100.0, 100.0, 1.0)] {
            let small = BadgeRenderer.rasterized(image(width: width, height: height), trimmingMargins: true)
            XCTAssertEqual(visibleRatio(of: menuBarImage(small)), ratio, accuracy: 0.12, "\(width)x\(height)")
        }
    }

    func testTrimmedImagesStillFillTheIconSpace() {
        let small = BadgeRenderer.rasterized(image(width: 200, height: 100), trimmingMargins: true)
        XCTAssertEqual(small.size, NSSize(width: BadgeRenderer.iconSize, height: BadgeRenderer.iconSize))
        // Margins are cropped, so the shape reaches both sides of the icon.
        XCTAssertEqual(visibleRatio(of: small), 2, accuracy: 0.12)
    }
}

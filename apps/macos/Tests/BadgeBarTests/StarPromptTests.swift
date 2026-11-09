import AppKit
import XCTest
@testable import BadgeBar

final class StarPromptTests: XCTestCase {
    func testGitHubMarkDecodesAndDrawsPixels() throws {
        let mark = try XCTUnwrap(StarPrompt.gitHubMark())
        XCTAssertEqual(mark.size, NSSize(width: 16, height: 16))

        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        mark.draw(in: NSRect(x: 0, y: 0, width: 32, height: 32))
        NSGraphicsContext.restoreGraphicsState()

        // The mark is a disc with a cat cut out: solid near the edge, not blank.
        let edge = try XCTUnwrap(bitmap.colorAt(x: 16, y: 2))
        XCTAssertGreaterThan(edge.alphaComponent, 0.5)
        let corner = try XCTUnwrap(bitmap.colorAt(x: 0, y: 0))
        XCTAssertEqual(corner.alphaComponent, 0, accuracy: 0.01)
    }
}

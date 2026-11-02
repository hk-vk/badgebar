import AppKit
import XCTest
@testable import BadgeBar

/// A badge without a number has its own color, separate from the count badge's.
final class ActivityColorTests: XCTestCase {
    private let icon = NSImage(size: NSSize(width: 16, height: 16))

    /// The most opaque pixel in the image, which is the badge since the icon is empty, as 0-255 RGBA.
    private func dotPixel(badge: String, appearance: BadgeAppearance, style: BadgeStyle = .dot) -> [Int] {
        var appearance = appearance
        appearance.style = style
        let image = BadgeRenderer.image(icon: icon, badge: Badge(label: badge), appearance: appearance)
        let width = Int(image.size.width * 4), height = Int(image.size.height * 4)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()

        var best = [0, 0, 0, 0]
        for y in 0..<height {
            for x in 0..<width {
                var pixel = [Int](repeating: 0, count: 4)
                rep.getPixel(&pixel, atX: x, y: y)
                // The dot's center, not its darker outline: the brightest fully drawn pixel wins.
                if pixel[3] > best[3] || (pixel[3] == best[3] && pixel[0] + pixel[1] + pixel[2] > best[0] + best[1] + best[2]) {
                    best = pixel
                }
            }
        }
        return best
    }

    private func assertColor(_ pixel: [Int], hex: String, file: StaticString = #filePath, line: UInt = #line) {
        let expected = NSColor(hex: hex)!.usingColorSpace(.deviceRGB)!
        let target = [expected.redComponent, expected.greenComponent, expected.blueComponent].map { Int($0 * 255) }
        for channel in 0..<3 {
            XCTAssertEqual(pixel[channel], target[channel], accuracy: 4, "\(pixel) is not \(hex)", file: file, line: line)
        }
    }

    func testActivityDotUsesTheChosenColorNotTheBadgeColor() {
        var appearance = BadgeAppearance()
        appearance.colorHex = "#FF3B30"
        appearance.activityColor = "#0A84FF"
        assertColor(dotPixel(badge: "•", appearance: appearance), hex: "#0A84FF")
        assertColor(dotPixel(badge: "•", appearance: appearance, style: .circle), hex: "#0A84FF")
    }

    func testCountBadgeStillUsesTheBadgeColor() {
        var appearance = BadgeAppearance()
        appearance.colorHex = "#FF3B30"
        appearance.activityColor = "#0A84FF"
        assertColor(dotPixel(badge: "3", appearance: appearance), hex: "#FF3B30")
    }

    func testDefaultActivityDotIsSolidGray() {
        let pixel = dotPixel(badge: "•", appearance: BadgeAppearance())
        XCTAssertEqual(pixel[3], 255, "the dot should be opaque so it shows over a white icon")
        assertColor(pixel, hex: BadgeAppearance.defaultActivityColor)
    }

    func testSettingsSavedBeforeThisColorExistedStillLoad() throws {
        let saved = ##"{"style":"dot","colorHex":"#34C759","emptyBehavior":"show"}"##
        let appearance = try JSONDecoder().decode(BadgeAppearance.self, from: Data(saved.utf8))
        XCTAssertEqual(appearance.style, .dot)
        XCTAssertEqual(appearance.colorHex, "#34C759")
        XCTAssertNil(appearance.activityColorHex)
        XCTAssertEqual(appearance.activityColor, BadgeAppearance.defaultActivityColor)
    }

    func testChosenColorSurvivesSaving() throws {
        var appearance = BadgeAppearance()
        appearance.activityColor = "#AF52DE"
        let saved = try JSONEncoder().encode(appearance)
        XCTAssertEqual(try JSONDecoder().decode(BadgeAppearance.self, from: saved).activityColor, "#AF52DE")
    }
}

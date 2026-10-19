import AppKit
import XCTest
@testable import BadgeBar

/// The preview must always hang just under the menu bar, under its icon, and stay on screen,
/// whatever vertical position macOS reports for the status button.
final class PreviewPlacementTests: XCTestCase {
    private let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)
    private let menuBarBottom: CGFloat = 982 - 37
    private let size = CGSize(width: 360, height: 300)

    private func frame(icon: NSRect, size: CGSize? = nil, screen: NSRect? = nil) -> NSRect {
        PreviewPopover.frame(for: size ?? self.size, under: icon, menuBarBottom: menuBarBottom, screen: screen ?? self.screen)
    }

    func testTopSitsJustUnderTheMenuBar() {
        let result = frame(icon: NSRect(x: 900, y: 950, width: 30, height: 24))
        XCTAssertEqual(result.maxY, menuBarBottom - 6)
        XCTAssertEqual(result.size, size)
    }

    func testIgnoresAWrongVerticalPositionForTheIcon() {
        // macOS 27 has reported status buttons hundreds of points down the screen, and above it.
        let right = frame(icon: NSRect(x: 900, y: 950, width: 30, height: 24))
        XCTAssertEqual(frame(icon: NSRect(x: 900, y: 370, width: 30, height: 24)), right)
        XCTAssertEqual(frame(icon: NSRect(x: 900, y: 2000, width: 30, height: 24)), right)
        XCTAssertEqual(frame(icon: NSRect(x: 900, y: 0, width: 30, height: 0)), right)
    }

    func testCentresOnTheIcon() {
        let result = frame(icon: NSRect(x: 900, y: 950, width: 30, height: 24))
        XCTAssertEqual(result.midX, 915)
    }

    func testStaysOnScreenNearTheRightEdge() {
        let result = frame(icon: NSRect(x: 1490, y: 950, width: 20, height: 24))
        XCTAssertEqual(result.maxX, screen.maxX - 8)
    }

    func testStaysOnScreenNearTheLeftEdge() {
        let result = frame(icon: NSRect(x: 2, y: 950, width: 20, height: 24))
        XCTAssertEqual(result.minX, 8)
    }

    func testTallContentIsShortenedRatherThanPushedOffTheTop() {
        let result = frame(icon: NSRect(x: 900, y: 950, width: 30, height: 24), size: CGSize(width: 360, height: 5000))
        XCTAssertEqual(result.maxY, menuBarBottom - 6)
        XCTAssertEqual(result.minY, 8)
    }

    func testWorksOnASecondScreen() {
        let second = NSRect(x: 1512, y: -200, width: 1920, height: 1080)
        let bottom = second.maxY - 24
        let result = PreviewPopover.frame(for: size, under: NSRect(x: 2500, y: 0, width: 30, height: 24), menuBarBottom: bottom, screen: second)
        XCTAssertEqual(result.maxY, bottom - 6)
        XCTAssertEqual(result.midX, 2515)
        XCTAssertTrue(second.contains(result))
    }
}

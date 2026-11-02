import AppKit
import XCTest
@testable import BadgeBar

/// Where the color panel goes: beside its window, and on screen.
final class ColorPanelPlacementTests: XCTestCase {
    private let screen = NSRect(x: 0, y: 0, width: 1470, height: 923)
    private let size = CGSize(width: 266, height: 366)

    private func origin(_ window: NSRect, screen: NSRect? = nil) -> NSPoint {
        ColorPanelPlacement.origin(for: size, beside: window, screen: screen ?? self.screen)
    }

    func testOpensOnTheRightWhenThereIsRoom() {
        let result = origin(NSRect(x: 100, y: 200, width: 820, height: 600))
        XCTAssertEqual(result, NSPoint(x: 932, y: 434))
    }

    func testOpensOnTheLeftWhenTheRightIsFull() {
        let result = origin(NSRect(x: 600, y: 200, width: 820, height: 600))
        XCTAssertEqual(result, NSPoint(x: 322, y: 434))
    }

    func testOverlapsAtTheScreenEdgeWhenNeitherSideHasRoom() {
        let result = origin(NSRect(x: 100, y: 100, width: 1270, height: 700))
        XCTAssertEqual(result.x, 1470 - 8 - 266)
    }

    func testStaysOnScreenVertically() {
        XCTAssertEqual(origin(NSRect(x: 100, y: 0, width: 820, height: 200)).y, 8)
        XCTAssertEqual(origin(NSRect(x: 100, y: 500, width: 820, height: 900)).y, 923 - 8 - 366)
    }

    func testWorksOnAScreenLeftOfTheMainOne() {
        let left = NSRect(x: -1920, y: 0, width: 1920, height: 1080)
        let result = origin(NSRect(x: -1800, y: 200, width: 820, height: 600), screen: left)
        XCTAssertEqual(result.x, -968)
        XCTAssertTrue(left.contains(NSRect(origin: result, size: size)))
    }
}

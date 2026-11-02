import AppKit
import SwiftUI
import XCTest
@testable import BadgeBar

/// The color panel loads only when asked for, and edits only the row that opened it.
@MainActor
final class ColorPanelSessionTests: XCTestCase {
    // One test, because the panel is a singleton and showing Settings must come before it exists.
    func testPanelLoadsOnDemandAndEditsOneRowAtATime() {
        let host = NSHostingView(rootView: Form {
            BadgeColorsSection(appearance: .constant(BadgeAppearance()))
        })
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 300)
        host.layoutSubtreeIfNeeded()
        _ = host.bitmapImageRepForCachingDisplay(in: host.bounds)
        ColorPanelSession.shared.end()
        XCTAssertFalse(NSColorPanel.sharedColorPanelExists, "showing the swatches must not load the panel")

        let session = ColorPanelSession()
        let first = UUID(), second = UUID()
        var firstColors: [String] = [], secondColors: [String] = []

        session.begin(owner: first, hex: "#0A84FF") { firstColors.append($0) }
        let panel = NSColorPanel.shared
        XCTAssertEqual(session.owner, first)
        XCTAssertEqual(panel.color.hexString, "#0A84FF")
        XCTAssertFalse(panel.showsAlpha)
        XCTAssertTrue(firstColors.isEmpty, "opening the panel must not change the color")

        panel.color = NSColor(hex: "#34C759")!
        XCTAssertEqual(firstColors.last, "#34C759")

        session.begin(owner: second, hex: "#AF52DE") { secondColors.append($0) }
        XCTAssertEqual(panel.color.hexString, "#AF52DE")
        let firstCount = firstColors.count
        panel.color = NSColor(hex: "#FF3B30")!
        XCTAssertEqual(firstColors.count, firstCount, "the first row must stop receiving colors")
        XCTAssertEqual(secondColors.last, "#FF3B30")

        session.sync(owner: first, hex: "#0A84FF")
        XCTAssertEqual(panel.color.hexString, "#FF3B30", "another row can't change what the panel shows")
        let beforeSync = secondColors.count
        session.sync(owner: second, hex: "#FF9500")
        XCTAssertEqual(secondColors.count, beforeSync, "sync must not save the color again")
        XCTAssertEqual(panel.color.hexString, "#FF9500")

        session.end(owner: first)
        XCTAssertEqual(session.owner, second, "another row going away changes nothing")
        panel.orderFront(nil)
        session.end()
        XCTAssertFalse(panel.isVisible, "closing Settings must hide the panel")
        XCTAssertNil(session.owner)
        let secondCount = secondColors.count
        panel.color = NSColor(hex: "#34C759")!
        XCTAssertEqual(secondColors.count, secondCount, "a finished row must not receive colors")

        session.begin(owner: first, hex: "#0A84FF") { firstColors.append($0) }
        panel.orderFront(nil)
        panel.close()
        XCTAssertNil(session.owner, "closing the panel must disconnect the row")
        let afterClose = firstColors.count
        panel.color = NSColor(hex: "#34C759")!
        XCTAssertEqual(firstColors.count, afterClose)
    }
}

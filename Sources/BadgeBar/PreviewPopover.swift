import AppKit
import SwiftUI

/// Shows a notification preview popover when the pointer rests on a menu bar item.
///
/// Behaves like the menu bar itself: once a preview is open, moving to a neighbouring item
/// switches to it immediately, and the preview stays open while the pointer is inside it.
@MainActor
final class PreviewPopover: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private var pending: DispatchWorkItem?
    private var pointerInPopover = false
    /// Opened by a click: stays open until the user clicks elsewhere, instead of on mouse-out.
    private var pinned = false
    private var outsideClickMonitor: Any?
    private(set) var anchorKey: String?

    var isShown: Bool { popover.isShown }
    var isPinned: Bool { popover.isShown && pinned }

    override init() {
        super.init()
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self
    }

    func hoverBegan(key: String, button: NSView, rect: NSRect? = nil, content: @escaping () -> AnyView) {
        pending?.cancel()
        if popover.isShown {
            if anchorKey != key { show(key: key, button: button, rect: rect, content: content(), pinned: false) }
            return
        }
        schedule(after: 0.35) { [weak self] in
            // A ⌘-drag in the menu bar may have started while waiting.
            guard !NSEvent.modifierFlags.contains(.command), NSEvent.pressedMouseButtons == 0 else { return }
            self?.show(key: key, button: button, rect: rect, content: content(), pinned: false)
        }
    }

    func hoverEnded(key: String) {
        pending?.cancel()
        guard popover.isShown, anchorKey == key, !pinned else { return }
        scheduleClose()
    }

    /// Opens (or toggles) the preview right away, e.g. on click.
    func toggle(key: String, button: NSView, rect: NSRect? = nil, content: AnyView) {
        pending?.cancel()
        if popover.isShown, anchorKey == key {
            close()
        } else {
            show(key: key, button: button, rect: rect, content: content, pinned: true)
        }
    }

    func close() {
        pending?.cancel()
        popover.performClose(nil)
        anchorKey = nil
    }

    private func show(key: String, button: NSView, rect: NSRect?, content: AnyView, pinned: Bool) {
        self.pinned = pinned
        let root = content
            .fixedSize()
            .onHover { [weak self] inside in
                guard let self else { return }
                self.pointerInPopover = inside
                if inside { self.pending?.cancel() } else if !self.pinned { self.scheduleClose() }
            }
            // Follow the content as cards are cleared or expanded.
            .onGeometryChange(for: CGSize.self, of: \.size) { [weak self] size in
                guard let self, self.popover.isShown, size.width > 0, size.height > 0 else { return }
                self.popover.contentSize = size
            }
            .environment(\.closePreview) { [weak self] in self?.close() }

        let hosting = FirstMouseHostingView(rootView: AnyView(root))
        hosting.frame.size = hosting.fittingSize
        let controller = NSViewController()
        controller.view = hosting

        popover.contentViewController = controller
        popover.contentSize = hosting.fittingSize
        anchorKey = key
        // Showing an already-open popover moves it to the new anchor.
        let anchor = rect ?? button.bounds
        // On macOS 27, maxY is the edge below the icon; other versions are checked on first use.
        let edge = Self.belowEdge ?? .maxY
        popover.show(relativeTo: anchor, of: button, preferredEdge: edge)
        if Self.belowEdge == nil { learnBelowEdge(tried: edge, anchor: anchor, button: button) }
        watchOutsideClicks()
    }

    /// The edge that puts the popover below a menu bar icon. Which edge that is depends on
    /// how the macOS version reports the status button's coordinates, so it's found by
    /// looking where the first popover actually landed.
    private static var belowEdge: NSRectEdge?

    private func learnBelowEdge(tried edge: NSRectEdge, anchor: NSRect, button: NSView) {
        guard let window = button.window, let popoverWindow = popover.contentViewController?.view.window else { return }
        let icon = window.convertToScreen(button.convert(anchor, to: nil))
        // Placeholder geometry (zero height) says nothing about where things landed.
        guard icon.height > 0 else { return }
        if popoverWindow.frame.maxY <= icon.minY + 2 {
            Self.belowEdge = edge
        } else {
            // It opened over or above the icon: the other edge is the one below.
            let other: NSRectEdge = edge == .minY ? .maxY : .minY
            Self.belowEdge = other
            popover.show(relativeTo: anchor, of: button, preferredEdge: other)
        }
    }

    /// Clicks in other apps close the popover, as with any menu bar popover.
    private func watchOutsideClicks() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func scheduleClose() {
        schedule(after: 0.3) { [weak self] in
            guard let self, !self.pointerInPopover else { return }
            self.close()
        }
    }

    private func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) {
        pending?.cancel()
        let work = DispatchWorkItem(block: action)
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func popoverDidClose(_ notification: Notification) {
        pointerInPopover = false
        pinned = false
        anchorKey = nil
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }
}

/// Lets buttons in the preview respond to the first click without activating BadgeBar first,
/// so hovering a preview never steals focus from the app you're working in.
final class FirstMouseHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct ClosePreviewKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var closePreview: () -> Void {
        get { self[ClosePreviewKey.self] }
        set { self[ClosePreviewKey.self] = newValue }
    }
}

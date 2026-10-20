import AppKit
import SwiftUI

/// Shows a notification preview under a menu bar item when it's clicked. It stays open until
/// the user clicks the item again or clicks anywhere else.
///
/// This is a panel placed at exact screen coordinates, not an NSPopover. macOS 27 reports a
/// status button's vertical position, and which popover edge counts as "below", differently
/// between launches, so NSPopover opened the preview far down the screen or off its top.
/// The panel hangs from the menu bar's bottom edge, which macOS always reports correctly.
@MainActor
final class PreviewPopover: NSObject {
    private var panel: PreviewPanel?
    private var outsideClickMonitor: Any?
    private var iconFrame: NSRect = .zero
    /// The preview's content; the panel is sized to fit it.
    private var hosting: FirstMouseHostingView?
    private var screen: NSScreen?
    private(set) var anchorKey: String?
    /// The preview closed by the last outside click, and when. Menu bar icons are drawn by
    /// another process on macOS 27, so clicking the preview's own icon also counts as an
    /// outside click: it closes the preview just before the icon's action runs.
    private var closedByClick: (key: String, time: Date)?

    var isShown: Bool { panel?.isVisible ?? false }

    /// Opens the preview, or closes it if it's already open for this item. `click` is where the
    /// icon was clicked, in screen coordinates.
    func toggle(key: String, button: NSView, rect: NSRect? = nil, click: NSPoint? = nil, content: AnyView) {
        let justClosed = closedByClick.map { $0.key == key && Date().timeIntervalSince($0.time) < 0.5 } ?? false
        closedByClick = nil
        if isShown, anchorKey == key {
            close()
        } else if justClosed {
            // This click already closed it; reopening would make the icon impossible to close.
            return
        } else {
            show(key: key, button: button, rect: rect, click: click, content: content)
        }
    }

    func close() {
        panel?.orderOut(nil)
        anchorKey = nil
        hosting = nil
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    private func show(key: String, button: NSView, rect: NSRect?, click: NSPoint?, content: AnyView) {
        let anchor = rect ?? button.bounds
        iconFrame = button.window?.convertToScreen(button.convert(anchor, to: nil)) ?? anchor
        screen = button.window?.screen ?? NSScreen.main
        // The button can report a made-up frame too (e.g. at the screen's left edge). Where the
        // user clicked is always on the icon, so centre on that when the two disagree.
        if let click, !(iconFrame.minX - 1...iconFrame.maxX + 1 ~= click.x) {
            iconFrame = NSRect(x: click.x - 11, y: iconFrame.minY, width: 22, height: iconFrame.height)
            screen = NSScreen.screens.first { $0.frame.contains(click) } ?? screen
        }

        let root = content
            .fixedSize()
            // Follow the content as cards are cleared or expanded.
            .onGeometryChange(for: CGSize.self, of: \.size) { [weak self] _ in
                // Measured afresh rather than using this size: it can arrive before the
                // panel is on screen, or mid-animation.
                DispatchQueue.main.async { self?.fitContent() }
            }
            .environment(\.closePreview) { [weak self] in self?.close() }

        let hosting = FirstMouseHostingView(rootView: AnyView(root))
        self.hosting = hosting
        let panel = self.panel ?? PreviewPanel()
        self.panel = panel
        panel.setContent(hosting)

        let opening = !panel.isVisible
        anchorKey = key
        fitContent()
        if opening {
            panel.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }
        watchOutsideClicks()
        // Text and images finish laying out once the panel is on screen; fit again then.
        DispatchQueue.main.async { [weak self] in self?.fitContent() }
    }

    /// Sizes the panel to its content's fully laid-out size. A panel shorter than its content
    /// cuts off the content's top, since SwiftUI centres it.
    private func fitContent() {
        guard let hosting, panel != nil else { return }
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        place(size: size)
    }

    private func place(size: CGSize) {
        guard let panel, let screen else { return }
        let frame = Self.frame(
            for: size,
            under: iconFrame,
            menuBarBottom: Self.menuBarBottom(of: screen),
            screen: screen.frame
        )
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    /// The bottom edge of the menu bar on this screen.
    static func menuBarBottom(of screen: NSScreen) -> CGFloat {
        min(screen.visibleFrame.maxY, screen.frame.maxY - NSStatusBar.system.thickness)
    }

    /// Where the preview goes: its top a small gap under the menu bar, centred on the icon and
    /// kept on screen. Only the icon's horizontal position is used, because its vertical
    /// position isn't reported reliably.
    nonisolated static func frame(
        for size: CGSize,
        under icon: NSRect,
        menuBarBottom: CGFloat,
        screen: NSRect,
        gap: CGFloat = 6,
        margin: CGFloat = 8
    ) -> NSRect {
        let top = menuBarBottom - gap
        let height = min(size.height, top - (screen.minY + margin))
        let width = min(size.width, screen.width - margin * 2)
        let centred = icon.midX - width / 2
        let x = min(max(centred, screen.minX + margin), screen.maxX - margin - width)
        return NSRect(x: x, y: top - height, width: width, height: height)
    }

    /// Clicks in other apps close the preview, as with any menu bar popover.
    private func watchOutsideClicks() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let key = self.anchorKey else { return }
                self.closedByClick = (key, Date())
                self.close()
            }
        }
    }
}

/// A borderless panel with the system popover material. It never becomes key, so using a
/// preview doesn't steal focus from the app you're working in.
private final class PreviewPanel: NSPanel {
    private let background = NSVisualEffectView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        isReleasedWhenClosed = false

        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 16
        background.layer?.cornerCurve = .continuous
        background.layer?.masksToBounds = true
        contentView = background
    }

    func setContent(_ view: NSView) {
        background.subviews.forEach { $0.removeFromSuperview() }
        view.frame = background.bounds
        view.autoresizingMask = [.width, .height]
        background.addSubview(view)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lets buttons in the preview respond to the first click without activating BadgeBar first,
/// so using a preview never steals focus from the app you're working in.
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

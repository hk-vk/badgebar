import AppKit
import SwiftUI

/// A small floating panel that follows System Settings while the user grants a permission.
///
/// It holds a draggable BadgeBar icon (dropping it into a privacy list adds the app) and
/// closes itself as soon as the permission is granted.
@MainActor
final class PermissionHelper {
    enum Kind {
        case accessibility, fullDiskAccess

        var title: String {
            switch self {
            case .accessibility: return "Switch on BadgeBar"
            case .fullDiskAccess: return "Drag BadgeBar into the list"
            }
        }

        var detail: String {
            switch self {
            case .accessibility: return "Not in the list? Drag this icon into it."
            case .fullDiskAccess: return "Then make sure its switch is on."
            }
        }

        @MainActor var isGranted: Bool {
            switch self {
            case .accessibility: return Permissions.hasAccessibility
            case .fullDiskAccess: return Permissions.hasFullDiskAccess
            }
        }
    }

    static let shared = PermissionHelper()

    private var panel: NSPanel?
    private var timer: Timer?
    private var kind: Kind?
    private var startedAt = Date()

    func show(_ kind: Kind) {
        close()
        self.kind = kind
        startedAt = Date()

        let view = HelperView(kind: kind) { [weak self] in self?.close() }
        let hosting = FirstMouseHostingView(rootView: AnyView(view))
        hosting.frame.size = hosting.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.panel = panel

        position()
        panel.orderFrontRegardless()

        // Follow System Settings as it opens or moves, and close once access is granted.
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func close() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
        kind = nil
    }

    private func tick() {
        guard let kind else { return }
        // Give up after a few minutes so the panel never lingers forever.
        if kind.isGranted || Date().timeIntervalSince(startedAt) > 300 {
            close()
            return
        }
        position()
    }

    /// Places the panel just below the System Settings window, or at the bottom of the screen.
    private func position() {
        guard let panel, let screen = NSScreen.main else { return }
        let size = panel.frame.size
        var origin = NSPoint(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.minY + 40
        )

        if let settings = Self.systemSettingsFrame() {
            let below = NSPoint(x: settings.midX - size.width / 2, y: settings.minY - size.height - 12)
            if below.y >= screen.visibleFrame.minY {
                origin = below
            } else {
                // Not enough room below: sit inside its bottom edge instead.
                origin = NSPoint(x: below.x, y: settings.minY + 16)
            }
        }
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
    }

    /// The frontmost System Settings window, in Cocoa screen coordinates.
    private static func systemSettingsFrame() -> NSRect? {
        guard
            let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
            let window = info.first(where: {
                ($0[kCGWindowOwnerName as String] as? String) == "System Settings"
                    && ($0[kCGWindowLayer as String] as? Int) == 0
            }),
            let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
            let primary = NSScreen.screens.first
        else { return nil }

        // Window list bounds are top-left based; Cocoa is bottom-left based.
        let rect = NSRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
        return NSRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }
}

private struct HelperView: View {
    let kind: PermissionHelper.Kind
    let close: () -> Void

    @State private var nudge = false

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 4) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .offset(y: nudge ? -3 : 0)
                    .onDrag { NSItemProvider(object: Bundle.main.bundleURL as NSURL) }
                    .help("Drag into the list in System Settings")
                Text("BadgeBar").font(.caption2.weight(.medium))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up").foregroundStyle(Color.brand)
                    Text(kind.title).font(.headline)
                }
                Text(kind.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassSurface(cornerRadius: 20)
        .padding(10)
        .onAppear {
            // A gentle bob draws the eye to the icon that needs dragging.
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { nudge = true }
        }
    }
}

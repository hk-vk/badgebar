import AppKit

/// Looks up and caches app icons and SF Symbols used across the UI.
@MainActor
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleID: String) -> NSImage {
        if let cached = cache[bundleID] { return cached }
        let image = url(for: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? symbol("questionmark.app")
        cache[bundleID] = image
        return image
    }

    /// The icon drawn in the menu bar for a tracked app, honoring its icon style.
    static func menuBarIcon(for app: TrackedApp) -> NSImage {
        let key = "\(app.bundleID)|\(app.iconStyle.rawValue)|\(app.customIconPath ?? "")"
        if let cached = cache[key] { return cached }

        let base = icon(for: app.bundleID)
        let image: NSImage
        switch app.iconStyle {
        case .original:
            image = base
        case .monochrome:
            image = BadgeRenderer.monochrome(base)
        case .custom:
            image = app.customIconPath.flatMap(NSImage.init(contentsOfFile:)) ?? base
        }
        cache[key] = image
        return image
    }

    static func symbol(_ name: String) -> NSImage {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "tray.full", accessibilityDescription: nil)!
        image.isTemplate = true
        return image
    }

    static func url(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    static func open(_ bundleID: String) {
        guard let url = url(for: bundleID) else { return }
        // openApplication (rather than activate) also reopens a window if the app has none.
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }
}

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

    /// The icon drawn in the menu bar for a tracked app, honoring its icon style. It's kept as
    /// a small bitmap at menu bar size, so the menu bar never holds on to full-size icons.
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
        let small = BadgeRenderer.rasterized(image, trimmingMargins: true)
        cache[key] = small
        return small
    }

    /// An untracked app's icon for the menu bar, trimmed and kept small like tracked ones.
    static func menuBarIcon(for bundleID: String) -> NSImage {
        let key = "\(bundleID)|auto"
        if let cached = cache[key] { return cached }
        let small = BadgeRenderer.rasterized(icon(for: bundleID), trimmingMargins: true)
        cache[key] = small
        return small
    }

    /// Drops full-size icons, keeping only the small menu bar ones. Settings and onboarding
    /// load dozens of icons for their lists; call this once they close.
    static func releaseLargeIcons() {
        cache = cache.filter { $0.key.contains("|") }
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

    /// Lowercased bundle IDs of every running app, for checking many apps at once.
    static func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() })
    }

    static func open(_ bundleID: String) {
        guard let url = url(for: bundleID) else { return }
        // openApplication (rather than activate) also reopens a window if the app has none.
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }
}

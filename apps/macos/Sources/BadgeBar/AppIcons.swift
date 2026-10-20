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
        if app.iconStyle == .custom, let name = app.customSymbol { return symbol(name) }
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

    /// The icon drawn in the menu bar for a group: its custom image, or else its symbol.
    static func menuBarIcon(for group: AppGroup) -> NSImage {
        guard let path = group.customIconPath else { return symbol(group.symbol) }
        let key = "group|\(path)"
        if let cached = cache[key] { return cached }
        guard let image = NSImage(contentsOfFile: path) else { return symbol(group.symbol) }
        let small = BadgeRenderer.rasterized(image, trimmingMargins: true)
        cache[key] = small
        return small
    }

    /// Where copies of images chosen as icons are kept.
    private static var customIconFolder: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("BadgeBar/Icons", isDirectory: true)
    }

    /// Copies an image chosen as an icon into BadgeBar's own folder, so the icon keeps working
    /// if the original is moved or deleted. Returns the copy's path.
    static func importCustomIcon(from url: URL) -> String? {
        guard let folder = customIconFolder, NSImage(contentsOf: url) != nil else { return nil }
        let copy = folder.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(url.pathExtension.isEmpty ? "png" : url.pathExtension)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: copy)
            return copy.path
        } catch {
            return nil
        }
    }

    /// Saves an app's icon as an image in BadgeBar's own folder, for using it as another
    /// item's icon. Returns the image's path.
    static func importAppIcon(_ bundleID: String) -> String? {
        guard let folder = customIconFolder else { return nil }
        var rect = NSRect(x: 0, y: 0, width: 256, height: 256)
        guard let cgImage = icon(for: bundleID).cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else { return nil }
        let copy = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: copy)
            return copy.path
        } catch {
            return nil
        }
    }

    /// An app's name as Finder shows it.
    static func name(for bundleID: String) -> String {
        url(for: bundleID).map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID
    }

    /// Deletes a copy made by `importCustomIcon`. Paths elsewhere (set by older versions,
    /// pointing at the user's own files) are left alone.
    static func removeCustomIcon(_ path: String?) {
        guard let path, let folder = customIconFolder, path.hasPrefix(folder.path + "/") else { return }
        try? FileManager.default.removeItem(atPath: path)
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

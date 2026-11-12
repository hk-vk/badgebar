import AppKit
import os

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
        if app.iconStyle == .custom, let name = app.customSymbol { return menuBarSymbol(name) }
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
        guard let path = group.customIconPath else { return menuBarSymbol(group.symbol) }
        let key = "group|\(path)"
        if let cached = cache[key] { return cached }
        guard let image = NSImage(contentsOfFile: path) else { return menuBarSymbol(group.symbol) }
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
        guard let data = try? Data(contentsOf: url) else { return nil }
        return saveCustomIcon(data, pathExtension: url.pathExtension)
    }

    /// Saves image data as an icon in BadgeBar's own folder, under a new name. Returns its path.
    static func saveCustomIcon(_ data: Data, pathExtension: String) -> String? {
        guard let folder = customIconFolder, NSImage(data: data) != nil else { return nil }
        let copy = folder.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(pathExtension.isEmpty ? "png" : pathExtension)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: copy)
            return copy.path
        } catch {
            return nil
        }
    }

    /// Saves an app's icon as an image in BadgeBar's own folder, for using it as another
    /// item's icon. Returns the image's path.
    static func importAppIcon(_ bundleID: String) -> String? {
        var rect = NSRect(x: 0, y: 0, width: 256, height: 256)
        guard let cgImage = icon(for: bundleID).cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else { return nil }
        return saveCustomIcon(png, pathExtension: "png")
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

    /// A symbol chosen as an icon, trimmed to fill the menu bar's icon space.
    private static func menuBarSymbol(_ name: String) -> NSImage {
        let key = "symbol|\(name)"
        if let cached = cache[key] { return cached }
        let image = BadgeRenderer.trimmedSymbol(symbol(name))
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

    /// Lowercased bundle IDs of every running app, for checking many apps at once.
    static func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() })
    }

    /// Opens an app, or brings it forward. Returns false if no app has that bundle ID.
    @discardableResult
    static func open(_ bundleID: String) -> Bool {
        guard let url = url(for: bundleID) else { return false }
        // openApplication (rather than activate) also reopens a window if the app has none.
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
        return true
    }

    private static let log = Logger(subsystem: "io.github.hk-vk.badgebar", category: "clicks")

    /// Opens an app, or hides it if it's the app you're using, so a second click on its icon
    /// puts it away again. That means it's the active app and owns the window on top. An app
    /// whose windows are closed or behind others is opened instead, which brings a window
    /// forward, as the Dock does. When in doubt it opens, which is harmless.
    static func toggle(_ bundleID: String, hidesWhenActive: Bool) {
        let target = bundleID.lowercased()
        // The active app alone isn't enough: it can have no windows (say, Finder after a click
        // on the desktop) while another app's window is on top. The window on top alone isn't
        // either: BadgeBar's own Settings window may be covering it.
        let top = topWindowOwner()
        let active = NSWorkspace.shared.frontmostApplication
        let inFront = top?.bundleIdentifier?.lowercased() == target
            && active?.bundleIdentifier?.lowercased() == target
        if hidesWhenActive, inFront, let top {
            let hidden = hide(top)
            log.debug("click \(bundleID, privacy: .public): in front, hide -> \(hidden)")
            // Opening it instead would only flash it, so a failed hide does nothing.
            return
        } else {
            log.debug("click \(bundleID, privacy: .public): top window \(top?.bundleIdentifier ?? "none", privacy: .public), active app \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none", privacy: .public), open")
        }
        open(bundleID)
    }

    /// Hides an app. macOS refuses `NSRunningApplication.hide()` from an app that isn't active,
    /// which BadgeBar isn't while its menu bar icons are clicked, so this goes through
    /// Accessibility, which BadgeBar has for reading badges.
    private static func hide(_ app: NSRunningApplication) -> Bool {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        if AXUIElementSetAttributeValue(element, kAXHiddenAttribute as CFString, kCFBooleanTrue) == .success {
            return true
        }
        return app.hide()
    }

    /// The app that owns the frontmost normal window on screen, ignoring BadgeBar's own
    /// windows and tiny or transparent helper windows. These details are readable without the
    /// Screen Recording permission. The list comes front to back.
    private static func topWindowOwner() -> NSRunningApplication? {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for window in windows {
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds),
                  rect.width > 50, rect.height > 50 else { continue }
            return NSRunningApplication(processIdentifier: pid)
        }
        return nil
    }
}

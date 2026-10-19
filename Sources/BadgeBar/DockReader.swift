import AppKit
import ApplicationServices

/// An application tile in the Dock.
struct DockEntry: Hashable {
    let name: String
    let bundleID: String
    let url: URL
    let badge: Badge?
}

/// Reads app badges from the Dock's accessibility tree.
///
/// Each app tile in the Dock is an `AXDockItem` whose `AXStatusLabel` attribute holds the
/// badge text (e.g. "3"). This works even when the Dock is auto-hidden, but needs the
/// Accessibility permission.
@MainActor
enum DockReader {
    private static var bundleIDCache: [URL: String] = [:]

    enum Access {
        case granted
        case denied
        /// Switched on in System Settings, but macOS won't apply it until BadgeBar relaunches.
        case needsRelaunch
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Checks access by actually talking to the Dock, since `AXIsProcessTrusted` alone can
    /// report a grant that hasn't taken effect for this process yet.
    static func access() -> Access {
        guard let dock = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return isTrusted ? .granted : .denied }

        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            AXUIElementCreateApplication(dock.processIdentifier), kAXChildrenAttribute as CFString, &value
        )
        switch result {
        case .success:
            return .granted
        case .apiDisabled:
            return isTrusted ? .needsRelaunch : .denied
        default:
            return isTrusted ? .granted : .denied
        }
    }

    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func read() -> [DockEntry] {
        guard let dock = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return [] }

        let root = AXUIElementCreateApplication(dock.processIdentifier)
        var entries: [DockEntry] = []
        for list in children(of: root) {
            for item in children(of: list) {
                guard
                    string(item, kAXSubroleAttribute) == "AXApplicationDockItem",
                    let url = attribute(item, kAXURLAttribute) as? URL,
                    let bundleID = bundleID(for: url)
                else { continue }

                let label = string(item, "AXStatusLabel")
                let badge = label.flatMap { $0.isEmpty ? nil : Badge(label: $0) }
                let name = string(item, kAXTitleAttribute) ?? url.deletingPathExtension().lastPathComponent
                entries.append(DockEntry(name: name, bundleID: bundleID, url: url, badge: badge))
            }
        }
        return entries
    }

    private static func bundleID(for url: URL) -> String? {
        if let cached = bundleIDCache[url] { return cached }
        let id = Bundle(url: url)?.bundleIdentifier
        bundleIDCache[url] = id
        return id
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }
}

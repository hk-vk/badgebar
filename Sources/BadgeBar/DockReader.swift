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

    /// One pass over the Dock: whether access works, and every app tile if it does.
    ///
    /// Checks access by actually talking to the Dock, since `AXIsProcessTrusted` alone can
    /// report a grant that hasn't taken effect for this process yet.
    static func read() -> (access: Access, entries: [DockEntry]) {
        guard let dock = dockElement() else { return (isTrusted ? .granted : .denied, []) }

        var value: AnyObject?
        switch AXUIElementCopyAttributeValue(dock, kAXChildrenAttribute as CFString, &value) {
        case .success:
            break
        case .apiDisabled:
            return (isTrusted ? .needsRelaunch : .denied, [])
        default:
            // The Dock may have restarted; look it up again next time.
            dockApp = nil
            return (isTrusted ? .granted : .denied, [])
        }

        var entries: [DockEntry] = []
        for list in (value as? [AXUIElement]) ?? [] {
            for item in children(of: list) {
                // One round trip per tile instead of one per attribute.
                var values: CFArray?
                guard
                    AXUIElementCopyMultipleAttributeValues(item, itemAttributes, [], &values) == .success,
                    let fields = values as? [AnyObject], fields.count == 4,
                    fields[0] as? String == "AXApplicationDockItem",
                    let url = fields[1] as? URL,
                    let bundleID = bundleID(for: url)
                else { continue }

                let label = fields[2] as? String
                let badge = label.flatMap { $0.isEmpty ? nil : Badge(label: $0) }
                let name = fields[3] as? String ?? url.deletingPathExtension().lastPathComponent
                entries.append(DockEntry(name: name, bundleID: bundleID, url: url, badge: badge))
            }
        }
        return (.granted, entries)
    }

    private static let itemAttributes = [
        kAXSubroleAttribute, kAXURLAttribute, "AXStatusLabel", kAXTitleAttribute,
    ] as CFArray

    private static var dockApp: (pid: pid_t, element: AXUIElement)?

    private static func dockElement() -> AXUIElement? {
        if let dockApp, NSRunningApplication(processIdentifier: dockApp.pid) != nil { return dockApp.element }
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return nil
        }
        let element = AXUIElementCreateApplication(dock.processIdentifier)
        dockApp = (dock.processIdentifier, element)
        return element
    }

    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
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

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }
}

import AppKit
import Combine

/// Owns every menu bar item: one per tracked app, one per group, auto items for untracked
/// badged apps, and BadgeBar's own icon.
@MainActor
final class StatusBarController: NSObject {
    private enum Kind {
        case main
        case app(bundleID: String, name: String, tracked: Bool)
        case group(UUID)
    }

    private struct Spec {
        let key: String
        let kind: Kind
        let image: NSImage
        let tooltip: String
        let visible: Bool
    }

    private let store: Store
    private let monitor: BadgeMonitor
    private let openSettings: () -> Void

    private var items: [String: NSStatusItem] = [:]
    private var kinds: [String: Kind] = [:]
    private var iconCache: [String: NSImage] = [:]
    private var cancellables: Set<AnyCancellable> = []

    init(store: Store, monitor: BadgeMonitor, openSettings: @escaping () -> Void) {
        self.store = store
        self.monitor = monitor
        self.openSettings = openSettings
        super.init()

        // @Published fires before the value changes, so hop to the next runloop turn
        // and coalesce bursts of changes into one rebuild.
        Publishers.MergeMany(
            store.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            monitor.objectWillChange.map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
        .sink { [weak self] in self?.rebuild() }
        .store(in: &cancellables)

        store.$apps
            .sink { [weak self] _ in self?.iconCache.removeAll() }
            .store(in: &cancellables)

        rebuild()
    }

    // MARK: - Building items

    func rebuild() {
        let badges = monitor.badges
        var specs: [Spec] = []

        for app in store.apps where app.groupID == nil {
            let badge = badges[app.bundleID]
            specs.append(Spec(
                key: "app.\(app.bundleID)",
                kind: .app(bundleID: app.bundleID, name: app.name, tracked: true),
                image: BadgeRenderer.image(icon: icon(for: app), badge: badge, appearance: app.appearance),
                tooltip: tooltip(app.name, badge),
                visible: badge != nil || app.appearance.emptyBehavior != .hide
            ))
        }

        for group in store.groups {
            let memberBadges = store.members(of: group).compactMap { badges[$0.bundleID] }
            let badge = Badge.combine(memberBadges)
            specs.append(Spec(
                key: "group.\(group.id.uuidString)",
                kind: .group(group.id),
                image: BadgeRenderer.image(icon: symbol(group.symbol), badge: badge, appearance: group.appearance),
                tooltip: tooltip(group.name, badge),
                visible: badge != nil || group.appearance.emptyBehavior != .hide
            ))
        }

        if store.general.autoShowBadgedApps {
            for entry in monitor.entries where entry.badge != nil && !store.isTracked(entry.bundleID) {
                specs.append(Spec(
                    key: "auto.\(entry.bundleID)",
                    kind: .app(bundleID: entry.bundleID, name: entry.name, tracked: false),
                    image: BadgeRenderer.image(icon: appIcon(entry.bundleID), badge: entry.badge, appearance: BadgeAppearance()),
                    tooltip: tooltip(entry.name, entry.badge),
                    visible: true
                ))
            }
        }

        // Always keep a way into the app: show our own icon when it's enabled, when
        // permission is missing, or when nothing else is on screen.
        let needsMain = store.general.showMainIcon || !monitor.isTrusted || !specs.contains(where: \.visible)
        let mainImage = symbol(monitor.isTrusted ? "app.badge" : "exclamationmark.triangle")
        specs.insert(Spec(
            key: "main",
            kind: .main,
            image: mainImage,
            tooltip: monitor.isTrusted ? "BadgeBar" : "BadgeBar needs Accessibility access",
            visible: needsMain
        ), at: 0)

        apply(specs)
    }

    private func apply(_ specs: [Spec]) {
        let wanted = Set(specs.map(\.key))
        for (key, item) in items where !wanted.contains(key) {
            NSStatusBar.system.removeStatusItem(item)
            items[key] = nil
            kinds[key] = nil
        }

        for spec in specs {
            let item = items[spec.key] ?? makeItem(key: spec.key)
            kinds[spec.key] = spec.kind
            if item.button?.image !== spec.image { item.button?.image = spec.image }
            item.button?.toolTip = spec.tooltip
            if item.isVisible != spec.visible { item.isVisible = spec.visible }
        }
    }

    private func makeItem(key: String) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Lets users ⌘-drag items into any order and have it remembered.
        item.autosaveName = "BadgeBar.\(key)"
        item.button?.identifier = NSUserInterfaceItemIdentifier(key)
        item.button?.target = self
        item.button?.action = #selector(clicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.imagePosition = .imageOnly
        items[key] = item
        return item
    }

    private func tooltip(_ name: String, _ badge: Badge?) -> String {
        guard let badge else { return name }
        return badge.count == nil ? "\(name) — new activity" : "\(name) — \(badge.label)"
    }

    // MARK: - Icons

    private func icon(for app: TrackedApp) -> NSImage {
        let cacheKey = "\(app.bundleID)|\(app.iconStyle.rawValue)|\(app.customIconPath ?? "")"
        if let cached = iconCache[cacheKey] { return cached }

        let base = appIcon(app.bundleID)
        let image: NSImage
        switch app.iconStyle {
        case .original:
            image = base
        case .monochrome:
            image = BadgeRenderer.monochrome(base)
        case .custom:
            image = app.customIconPath.flatMap(NSImage.init(contentsOfFile:)) ?? base
        }
        iconCache[cacheKey] = image
        return image
    }

    private func appIcon(_ bundleID: String) -> NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return symbol("questionmark.app")
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private func symbol(_ name: String) -> NSImage {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "tray.full", accessibilityDescription: nil)!
        image.isTemplate = true
        return image
    }

    // MARK: - Clicks

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let key = sender.identifier?.rawValue, let kind = kinds[key] else { return }
        let event = NSApp.currentEvent
        let secondary = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true

        switch (kind, secondary) {
        case (.main, _):
            show(mainMenu(), from: sender)
        case let (.app(bundleID, _, _), false):
            Self.open(bundleID)
        case let (.app(bundleID, name, tracked), true):
            show(appMenu(bundleID: bundleID, name: name, tracked: tracked), from: sender)
        case let (.group(id), _):
            show(groupMenu(id), from: sender)
        }
    }

    private func show(_ menu: NSMenu, from button: NSStatusBarButton) {
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }

    static func open(_ bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        // openApplication (rather than activate) also reopens a window if the app has none.
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    // MARK: - Menus

    private func mainMenu() -> NSMenu {
        let menu = NSMenu()
        if !monitor.isTrusted {
            menu.addItem(ClosureMenuItem("Grant Accessibility Access…") { DockReader.requestTrust() })
            menu.addItem(.separator())
        }

        let badged = monitor.entries.filter { $0.badge != nil }
        if badged.isEmpty {
            let empty = NSMenuItem(title: monitor.isTrusted ? "No notifications" : "Waiting for permission", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for entry in badged {
                menu.addItem(appItem(bundleID: entry.bundleID, name: entry.name, badge: entry.badge))
            }
        }

        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Settings…", key: ",") { [openSettings] in openSettings() })
        menu.addItem(ClosureMenuItem("Quit BadgeBar", key: "q") { NSApp.terminate(nil) })
        return menu
    }

    private func appMenu(bundleID: String, name: String, tracked: Bool) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("Open \(name)") { Self.open(bundleID) })
        if !tracked {
            menu.addItem(ClosureMenuItem("Keep \(name) in Menu Bar") { [store] in
                store.track(bundleID: bundleID, name: name)
            })
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Settings…", key: ",") { [openSettings] in openSettings() })
        menu.addItem(ClosureMenuItem("Quit BadgeBar", key: "q") { NSApp.terminate(nil) })
        return menu
    }

    private func groupMenu(_ id: UUID) -> NSMenu {
        let menu = NSMenu()
        guard let group = store.groups.first(where: { $0.id == id }) else { return menu }
        let badges = monitor.badges
        let members = store.members(of: group)
        if members.isEmpty {
            let empty = NSMenuItem(title: "No apps in this group", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for app in members {
            menu.addItem(appItem(bundleID: app.bundleID, name: app.name, badge: badges[app.bundleID]))
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Settings…", key: ",") { [openSettings] in openSettings() })
        return menu
    }

    private func appItem(bundleID: String, name: String, badge: Badge?) -> NSMenuItem {
        let title = badge.map { "\(name)  (\($0.count == nil ? "•" : BadgeRenderer.displayLabel($0)))" } ?? name
        let item = ClosureMenuItem(title) { Self.open(bundleID) }
        let icon = appIcon(bundleID).copy() as! NSImage
        icon.size = NSSize(width: 16, height: 16)
        item.image = icon
        return item
    }
}

/// NSMenuItem that runs a closure when chosen.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}

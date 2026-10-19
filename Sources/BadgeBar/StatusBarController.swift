import AppKit
import Combine
import SwiftUI

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
    private let openSettings: (SidebarItem?) -> Void
    private let openGuide: () -> Void
    private let preview = PreviewPopover()

    private var items: [String: NSStatusItem] = [:]
    private var kinds: [String: Kind] = [:]
    private var trackers: [String: HoverTracker] = [:]
    private var cancellables: Set<AnyCancellable> = []

    init(
        store: Store,
        monitor: BadgeMonitor,
        openSettings: @escaping (SidebarItem?) -> Void,
        openGuide: @escaping () -> Void
    ) {
        self.store = store
        self.monitor = monitor
        self.openSettings = openSettings
        self.openGuide = openGuide
        super.init()

        // @Published fires before the value changes, so hop to the next runloop turn
        // and coalesce bursts of changes into one rebuild.
        Publishers.Merge(
            store.objectWillChange.map { _ in () },
            monitor.objectWillChange.map { _ in () }
        )
        .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
        .sink { [weak self] in self?.rebuild() }
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
                image: BadgeRenderer.image(icon: AppIcons.menuBarIcon(for: app), badge: badge, appearance: app.appearance),
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
                image: BadgeRenderer.image(icon: AppIcons.symbol(group.symbol), badge: badge, appearance: group.appearance),
                tooltip: tooltip(group.name, badge),
                visible: badge != nil || group.appearance.emptyBehavior != .hide
            ))
        }

        if store.general.autoShowBadgedApps {
            for entry in monitor.entries where entry.badge != nil && !store.isTracked(entry.bundleID) {
                specs.append(Spec(
                    key: "auto.\(entry.bundleID)",
                    kind: .app(bundleID: entry.bundleID, name: entry.name, tracked: false),
                    image: BadgeRenderer.image(icon: AppIcons.icon(for: entry.bundleID), badge: entry.badge, appearance: BadgeAppearance()),
                    tooltip: tooltip(entry.name, entry.badge),
                    visible: true
                ))
            }
        }

        // Always keep a way into the app: show our own icon when it's enabled, when
        // permission is missing, or when nothing else is on screen.
        let needsMain = store.general.showMainIcon || !monitor.isTrusted || !specs.contains(where: \.visible)
        specs.insert(Spec(
            key: "main",
            kind: .main,
            image: AppIcons.symbol(monitor.isTrusted ? "app.badge" : "exclamationmark.triangle"),
            tooltip: monitor.isTrusted ? "BadgeBar" : "BadgeBar needs Accessibility access",
            visible: needsMain
        ), at: 0)

        apply(specs)
    }

    private func apply(_ specs: [Spec]) {
        let wanted = Set(specs.map(\.key))
        for (key, item) in items where !wanted.contains(key) {
            if preview.anchorKey == key { preview.close() }
            NSStatusBar.system.removeStatusItem(item)
            items[key] = nil
            kinds[key] = nil
            trackers[key] = nil
        }

        for spec in specs {
            let item = items[spec.key] ?? makeItem(key: spec.key)
            kinds[spec.key] = spec.kind
            item.button?.image = spec.image
            // Hovering shows a richer preview, so skip the tooltip that would cover it.
            item.button?.toolTip = store.general.showHoverPreviews && spec.key != "main" ? nil : spec.tooltip
            item.button?.setAccessibilityLabel(spec.tooltip)
            if item.isVisible != spec.visible { item.isVisible = spec.visible }
        }
    }

    private func makeItem(key: String) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Lets users ⌘-drag items into any order and have it remembered.
        item.autosaveName = "BadgeBar.\(key)"
        if let button = item.button {
            button.identifier = NSUserInterfaceItemIdentifier(key)
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
            if key != "main" {
                trackers[key] = HoverTracker(view: button) { [weak self, weak button] inside in
                    guard let self, let button else { return }
                    self.hoverChanged(key: key, button: button, inside: inside)
                }
            }
        }
        items[key] = item
        return item
    }

    private func tooltip(_ name: String, _ badge: Badge?) -> String {
        guard let badge else { return name }
        return badge.count == nil ? "\(name) — new activity" : "\(name) — \(badge.label)"
    }

    // MARK: - Hover previews

    private func hoverChanged(key: String, button: NSView, inside: Bool) {
        guard store.general.showHoverPreviews else { return }
        if inside {
            preview.hoverBegan(key: key, button: button) { [weak self] in
                self?.previewContent(for: key) ?? AnyView(EmptyView())
            }
        } else {
            preview.hoverEnded(key: key)
        }
    }

    private func previewContent(for key: String) -> AnyView {
        guard let kind = kinds[key] else { return AnyView(EmptyView()) }
        let model = viewerModel(for: kind)
        return AnyView(NotificationViewer(model: model, store: store) { [weak self] in
            switch kind {
            case let .group(id): self?.openSettings(.group(id))
            case let .app(bundleID, _, true): self?.openSettings(.app(bundleID))
            default: self?.openSettings(nil)
            }
        })
    }

    private func viewerModel(for kind: Kind) -> ViewerModel {
        let badges = monitor.badges
        let canRead = Permissions.hasFullDiskAccess
        let showContent = store.general.showMessageContent
        let fetch = canRead && showContent

        func apps(_ list: [(bundleID: String, name: String)], notes: [DeliveredNotification]) -> [AppNotifications] {
            list.map { app in
                AppNotifications(
                    bundleID: app.bundleID,
                    name: app.name,
                    badge: badges[app.bundleID],
                    isRunning: AppIcons.isRunning(app.bundleID),
                    notifications: notes.filter { $0.bundleID.caseInsensitiveCompare(app.bundleID) == .orderedSame }
                )
            }
        }

        switch kind {
        case let .app(bundleID, name, _):
            let notes = fetch ? NotificationDatabase.recent(for: [bundleID], limit: 20) : []
            return ViewerModel(
                scope: .app(bundleID: bundleID),
                title: name,
                badge: badges[bundleID],
                apps: apps([(bundleID, name)], notes: notes),
                canReadNotifications: canRead,
                showsContent: showContent
            )

        case let .group(id):
            let group = store.groups.first { $0.id == id }
            let members = group.map(store.members(of:)) ?? []
            let notes = fetch ? NotificationDatabase.recent(for: members.map(\.bundleID), limit: 60) : []
            let list = apps(members.map { ($0.bundleID, $0.name) }, notes: notes)
            return ViewerModel(
                scope: .group(symbol: group?.symbol ?? "tray.full"),
                title: group?.name ?? "Group",
                badge: Badge.combine(members.compactMap { badges[$0.bundleID] }),
                apps: sortByActivity(list),
                canReadNotifications: canRead,
                showsContent: showContent
            )

        case .main:
            // Every app with a badge or recent notifications, newest activity first.
            let notes = fetch ? NotificationDatabase.recent(for: nil, limit: 120) : []
            var seen = Set<String>()
            var list: [(bundleID: String, name: String)] = []
            for entry in monitor.entries where entry.badge != nil && seen.insert(entry.bundleID.lowercased()).inserted {
                list.append((entry.bundleID, entry.name))
            }
            for note in notes where seen.insert(note.bundleID.lowercased()).inserted {
                list.append((resolveBundleID(note.bundleID), displayName(note.bundleID)))
            }
            return ViewerModel(
                scope: .all,
                title: "Notifications",
                badge: Badge.combine(Array(badges.values)),
                apps: sortByActivity(apps(list, notes: notes)),
                canReadNotifications: canRead,
                showsContent: showContent
            )
        }
    }

    private func sortByActivity(_ apps: [AppNotifications]) -> [AppNotifications] {
        apps.sorted { a, b in
            let da = a.notifications.first(where: store.isVisible)?.date ?? .distantPast
            let db = b.notifications.first(where: store.isVisible)?.date ?? .distantPast
            if da != db { return da > db }
            return (a.badge != nil ? 0 : 1) < (b.badge != nil ? 0 : 1)
        }
    }

    /// Notification Center often stores bundle IDs lowercased; prefer the real spelling.
    private func resolveBundleID(_ id: String) -> String {
        if let entry = monitor.entries.first(where: { $0.bundleID.caseInsensitiveCompare(id) == .orderedSame }) {
            return entry.bundleID
        }
        if let url = AppIcons.url(for: id), let real = Bundle(url: url)?.bundleIdentifier { return real }
        return id
    }

    private func displayName(_ id: String) -> String {
        if let entry = monitor.entries.first(where: { $0.bundleID.caseInsensitiveCompare(id) == .orderedSame }) {
            return entry.name
        }
        if let url = AppIcons.url(for: id) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return id
    }

    // MARK: - Clicks

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let key = sender.identifier?.rawValue, let kind = kinds[key] else { return }
        let event = NSApp.currentEvent
        let secondary = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true

        if secondary { preview.close() }

        switch (kind, secondary) {
        case (.main, false) where monitor.isTrusted:
            preview.toggle(key: key, button: sender, content: previewContent(for: key))
        case (.main, _):
            preview.close()
            show(mainMenu(), from: sender)
        case let (.app(bundleID, _, _), false):
            preview.close()
            AppIcons.open(bundleID)
        case let (.app(bundleID, name, tracked), true):
            show(appMenu(bundleID: bundleID, name: name, tracked: tracked), from: sender)
        case (.group, false):
            preview.toggle(key: key, button: sender, content: previewContent(for: key))
        case let (.group(id), true):
            show(groupMenu(id), from: sender)
        }
    }

    private func show(_ menu: NSMenu, from button: NSStatusBarButton) {
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }

    // MARK: - Menus

    private func mainMenu() -> NSMenu {
        let menu = NSMenu()
        if monitor.needsRelaunch {
            menu.addItem(ClosureMenuItem("Restart BadgeBar to Finish Setup") { Permissions.relaunch() })
            menu.addItem(.separator())
        } else if !monitor.isTrusted {
            let setup = ClosureMenuItem("Finish Setting Up BadgeBar…") { [openGuide] in openGuide() }
            setup.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
            menu.addItem(setup)
            menu.addItem(.separator())
        }

        let badged = monitor.entries.filter { $0.badge != nil }
        menu.addItem(.sectionHeader(title: "Notifications"))
        if badged.isEmpty {
            let empty = NSMenuItem(title: monitor.isTrusted ? "You're all caught up" : "Waiting for permission", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for entry in badged {
                menu.addItem(appItem(bundleID: entry.bundleID, name: entry.name, badge: entry.badge))
            }
        }

        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Settings…", key: ",") { [openSettings] in openSettings(nil) })
        menu.addItem(ClosureMenuItem("Welcome Guide") { [openGuide] in openGuide() })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Quit BadgeBar", key: "q") { NSApp.terminate(nil) })
        return menu
    }

    private func appMenu(bundleID: String, name: String, tracked: Bool) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("Open \(name)") { AppIcons.open(bundleID) })
        menu.addItem(.separator())
        if tracked {
            menu.addItem(ClosureMenuItem("Customize…") { [openSettings] in openSettings(.app(bundleID)) })
            menu.addItem(ClosureMenuItem("Remove from Menu Bar") { [store] in
                store.apps.removeAll { $0.bundleID == bundleID }
            })
        } else {
            menu.addItem(ClosureMenuItem("Keep in Menu Bar") { [store] in
                store.track(bundleID: bundleID, name: name)
            })
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Settings…", key: ",") { [openSettings] in openSettings(nil) })
        return menu
    }

    private func groupMenu(_ id: UUID) -> NSMenu {
        let menu = NSMenu()
        guard let group = store.groups.first(where: { $0.id == id }) else { return menu }
        let badges = monitor.badges
        menu.addItem(.sectionHeader(title: group.name))
        for app in store.members(of: group) {
            menu.addItem(appItem(bundleID: app.bundleID, name: app.name, badge: badges[app.bundleID]))
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Customize Group…") { [openSettings] in openSettings(.group(id)) })
        return menu
    }

    private func appItem(bundleID: String, name: String, badge: Badge?) -> NSMenuItem {
        let item = ClosureMenuItem(name) { AppIcons.open(bundleID) }
        let icon = AppIcons.icon(for: bundleID).copy() as! NSImage
        icon.size = NSSize(width: 16, height: 16)
        item.image = icon
        if let badge {
            item.badge = badge.count.map { NSMenuItemBadge(count: $0) } ?? NSMenuItemBadge(string: "•")
        }
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

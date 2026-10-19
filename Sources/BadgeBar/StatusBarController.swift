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

    /// Extra width around each icon. None: macOS already spaces separate items apart.
    private static let itemPadding: CGFloat = 0

    private let store: Store
    private let monitor: BadgeMonitor
    private let openSettings: (SidebarItem?) -> Void
    private let openGuide: () -> Void
    /// Where the open menu came from, so its items can show a preview from the same icon.
    private var menuSource: NSStatusBarButton?
    private let preview = PreviewPopover()

    private var items: [String: NSStatusItem] = [:]
    private var kinds: [String: Kind] = [:]
    private var pointerMonitors: [Any] = []
    /// Tracking areas don't retain their owners.
    private var hoverTrackers: [String: HoverTracker] = [:]
    /// The order of app and group items last put in the menu bar.
    private var appliedOrder: [String]?
    /// Bumped each time BadgeBar re-adds its items in a new order. macOS remembers each item's
    /// spot by its autosave name and offers no way to clear it, so re-added items get fresh names.
    private var itemGeneration = UserDefaults.standard.integer(forKey: "statusItemGeneration") {
        didSet { UserDefaults.standard.set(itemGeneration, forKey: "statusItemGeneration") }
    }
    /// The item under the pointer, for hover previews.
    private var hoveredKey: String?
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
        watchPointer()
    }

    // MARK: - Building items

    func rebuild() {
        if monitor.isTrusted {
            let canRead = Permissions.hasFullDiskAccess
            store.refreshAcknowledged(current: monitor.badges) { id in
                canRead ? NotificationDatabase.recent(for: [id], limit: 1).first?.date : nil
            }
        }
        // Badges the user marked as read stay hidden until the count goes up.
        let badges = store.visibleBadges(monitor.badges)
        var specs: [Spec] = []

        for app in store.apps where app.groupID == nil {
            let badge = badges[app.bundleID]
            let appearance = app.appearance.resolved(store.general)
            specs.append(Spec(
                key: "app.\(app.bundleID)",
                kind: .app(bundleID: app.bundleID, name: app.name, tracked: true),
                image: BadgeRenderer.image(icon: AppIcons.menuBarIcon(for: app), badge: badge, appearance: appearance),
                tooltip: tooltip(app.name, badge),
                visible: badge != nil || appearance.emptyBehavior != .hide
            ))
        }

        for group in store.groups {
            let memberBadges = store.members(of: group).compactMap { badges[$0.bundleID] }
            let badge = Badge.combine(memberBadges)
            let appearance = group.appearance.resolved(store.general)
            specs.append(Spec(
                key: "group.\(group.id.uuidString)",
                kind: .group(group.id),
                image: BadgeRenderer.image(icon: AppIcons.symbol(group.symbol), badge: badge, appearance: appearance),
                tooltip: tooltip(group.name, badge),
                visible: badge != nil || appearance.emptyBehavior != .hide
            ))
        }

        if store.general.autoShowBadgedApps {
            for entry in monitor.entries where !store.isTracked(entry.bundleID) {
                guard let badge = badges[entry.bundleID] else { continue }
                specs.append(Spec(
                    key: "auto.\(entry.bundleID)",
                    kind: .app(bundleID: entry.bundleID, name: entry.name, tracked: false),
                    image: BadgeRenderer.image(icon: AppIcons.icon(for: entry.bundleID), badge: badge, appearance: BadgeAppearance()),
                    tooltip: tooltip(entry.name, badge),
                    visible: true
                ))
            }
        }

        // Our own icon only appears when asked for, or when permission is missing and the
        // user needs a way back to set it up. Otherwise reopening the app opens Settings.
        let needsMain = store.general.showMainIcon || !monitor.isTrusted
        specs.insert(Spec(
            key: "main",
            kind: .main,
            image: BadgeRenderer.image(
                icon: AppIcons.symbol(monitor.isTrusted ? "app.badge" : "exclamationmark.triangle"),
                badge: nil,
                appearance: BadgeAppearance(emptyBehavior: .show)
            ),
            tooltip: monitor.isTrusted ? "BadgeBar" : "BadgeBar needs Accessibility access",
            visible: needsMain
        ), at: 0)

        applyItems(specs)
    }

    private func applyItems(_ specs: [Spec]) {
        let wanted = Set(specs.map(\.key))
        for (key, item) in items where !wanted.contains(key) {
            if preview.anchorKey == key { preview.close() }
            NSStatusBar.system.removeStatusItem(item)
            items[key] = nil
            kinds[key] = nil
            hoverTrackers[key] = nil
        }

        let order = specs.map(\.key).filter(Self.isOrdered)
        if let appliedOrder, appliedOrder != order {
            recreateItems(order)
        } else if appliedOrder == nil {
            // macOS doesn't tell apps where their items sit, so the order in Settings is the
            // one source of truth. Start under fresh names so old ⌘-drag spots don't override it.
            itemGeneration += 1
        }
        appliedOrder = order

        // macOS places each new item to the left of the existing ones, so create right to left.
        for spec in specs.reversed() where items[spec.key] == nil {
            _ = makeItem(key: spec.key)
        }

        for spec in specs {
            guard let item = items[spec.key] else { continue }
            kinds[spec.key] = spec.kind
            item.button?.image = spec.image
            // A fixed width that hugs the image. Variable-length items add generous padding on
            // both sides, which spreads several badge icons too far apart.
            item.length = ceil(spec.image.size.width) + Self.itemPadding
            // Hovering shows a richer preview, so skip the tooltip that would cover it.
            item.button?.toolTip = store.general.showHoverPreviews && spec.key != "main" ? nil : spec.tooltip
            item.button?.setAccessibilityLabel(spec.tooltip)
            if item.isVisible != spec.visible { item.isVisible = spec.visible }
        }
    }

    // MARK: - Order

    /// App and group items follow the order set in Settings. Auto-shown items come and go, so
    /// they don't take part.
    private static func isOrdered(_ key: String) -> Bool {
        key.hasPrefix("app.") || key.hasPrefix("group.")
    }

    /// Puts items back in the given order: removes them, then adds them again under fresh
    /// autosave names, right to left, so macOS places them as new items instead of restoring
    /// their old spots.
    private func recreateItems(_ order: [String]) {
        preview.close()
        hoveredKey = nil
        for key in order {
            if let item = items[key] { NSStatusBar.system.removeStatusItem(item) }
            items[key] = nil
        }
        itemGeneration += 1
        for key in order.reversed() { _ = makeItem(key: key) }
    }

    private func makeItem(key: String) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // macOS remembers each item's spot by this name.
        item.autosaveName = Self.isOrdered(key) && itemGeneration > 0
            ? "BadgeBar.\(key).\(itemGeneration)"
            : "BadgeBar.\(key)"
        if let button = item.button {
            button.identifier = NSUserInterfaceItemIdentifier(key)
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
            let tracker = HoverTracker(key: key, controller: self)
            button.addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: tracker,
                userInfo: nil
            ))
            hoverTrackers[key] = tracker
        }
        items[key] = item
        return item
    }

    private func tooltip(_ name: String, _ badge: Badge?) -> String {
        guard let badge else { return name }
        return badge.count == nil ? "\(name) — new activity" : "\(name) — \(badge.label)"
    }

    // MARK: - Hover previews

    /// Watches the pointer everywhere, for macOS versions that report where items sit. Newer
    /// ones draw items in a system process and only report placeholder frames; there the
    /// tracking areas added in `makeItem` take over.
    private func watchPointer() {
        let moved: () -> Void = { [weak self] in MainActor.assumeIsolated { self?.pointerMoved() } }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { _ in moved() }) {
            pointerMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { event in moved(); return event }) {
            pointerMonitors.append(local)
        }
    }

    private func pointerMoved() {
        let location = NSEvent.mouseLocation
        // Mouse moves arrive constantly from every app. Skip the item lookup unless the pointer
        // is in a menu bar, or is just leaving an item.
        guard hoveredKey != nil || Self.isInMenuBar(location), hasGeometry else { return }
        let hit = item(at: location)
        hoverChanged(to: hit?.key, button: hit?.button)
    }

    private var hasGeometry: Bool {
        items.values.contains { ($0.button?.window?.frame.height ?? 0) > 0 }
    }

    fileprivate func pointer(enteredKey key: String, inside: Bool) {
        HoverLog.write("tracking \(inside ? "enter" : "exit") \(key) frame=\(items[key]?.button?.window?.frame ?? .zero)") // TEMP-HOVERLOG
        if inside {
            hoverChanged(to: key, button: items[key]?.button)
        } else if hoveredKey == key {
            hoverChanged(to: nil, button: nil)
        }
    }

    private func hoverChanged(to key: String?, button: NSStatusBarButton?) {
        guard key != hoveredKey else { return }
        if let old = hoveredKey { preview.hoverEnded(key: old) }
        hoveredKey = key
        guard let key, let button, store.general.showHoverPreviews else { return }
        preview.hoverBegan(key: key, button: button) { [weak self] in
            self?.previewContent(for: key) ?? AnyView(EmptyView())
        }
    }

    private static func isInMenuBar(_ location: NSPoint) -> Bool {
        NSScreen.screens.contains { screen in
            let frame = screen.frame
            let barHeight = max(frame.maxY - screen.visibleFrame.maxY, 24)
            return location.x >= frame.minX && location.x <= frame.maxX
                && location.y >= frame.maxY - barHeight && location.y <= frame.maxY
        }
    }

    /// The menu bar item under a screen point.
    private func item(at location: NSPoint) -> (key: String, button: NSStatusBarButton)? {
        for (key, item) in items where key != "main" && item.isVisible {
            guard let button = item.button, let window = button.window else { continue }
            let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
            // The menu bar's top pixel row counts too, so pushing against the screen edge works.
            guard frame.insetBy(dx: 0, dy: -1).contains(location) else { continue }
            return (key, button)
        }
        return nil
    }

    private func previewContent(for key: String, history: Bool = false) -> AnyView {
        guard let kind = kinds[key] else { return AnyView(EmptyView()) }
        let model = viewerModel(for: kind, history: history)
        let markRead: ([String]) -> Void = { [weak self] ids in
            guard let self else { return }
            self.store.markRead(ids, badges: self.monitor.badges)
        }
        return AnyView(NotificationViewer(model: model, store: store, markRead: markRead) { [weak self] in
            switch kind {
            case let .group(id): self?.openSettings(.group(id))
            case let .app(bundleID, _, true): self?.openSettings(.app(bundleID))
            default: self?.openSettings(nil)
            }
        })
    }

    /// History includes messages already marked as read and reaches further back.
    private func viewerModel(for kind: Kind, history: Bool = false) -> ViewerModel {
        let limit = history ? 200 : 60
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
            let notes = fetch ? NotificationDatabase.recent(for: [bundleID], limit: limit) : []
            return ViewerModel(
                scope: .app(bundleID: bundleID),
                title: name,
                apps: apps([(bundleID, name)], notes: notes),
                canReadNotifications: canRead,
                showsContent: showContent,
                includesRead: history
            )

        case let .group(id):
            let group = store.groups.first { $0.id == id }
            let members = group.map(store.members(of:)) ?? []
            let notes = fetch ? NotificationDatabase.recent(for: members.map(\.bundleID), limit: limit) : []
            let list = apps(members.map { ($0.bundleID, $0.name) }, notes: notes)
            return ViewerModel(
                scope: .group(symbol: group?.symbol ?? "tray.full"),
                title: group?.name ?? "Group",
                apps: sortByActivity(list),
                canReadNotifications: canRead,
                showsContent: showContent,
                includesRead: history
            )

        case .main:
            // Every app with a badge or recent notifications, newest activity first.
            let notes = fetch ? NotificationDatabase.recent(for: nil, limit: history ? 300 : 120) : []
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
        HoverLog.write("click \(sender.identifier?.rawValue ?? "") mouse=\(NSEvent.mouseLocation) frame=\(sender.window?.frame ?? .zero) geometry=\(hasGeometry)") // TEMP-HOVERLOG
        guard let key = sender.identifier?.rawValue else { return }
        let event = NSApp.currentEvent
        guard let kind = kinds[key] else { return }
        let secondary = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if secondary { preview.close() }
        menuSource = sender

        switch (kind, secondary) {
        case (.main, false) where monitor.isTrusted:
            preview.toggle(key: key, button: sender, content: previewContent(for: key))
        case (.main, _):
            preview.close()
            show(mainMenu(), from: sender)
        case let (.app(bundleID, _, _), false):
            // Like a Dock icon: a click opens the app. Messages are a hover or right-click away.
            preview.close()
            AppIcons.open(bundleID)
        case let (.app(bundleID, name, tracked), true):
            show(appMenu(key: key, bundleID: bundleID, name: name, tracked: tracked), from: sender)
        case (.group, false):
            // A group has no single app to open, so a click shows its messages.
            preview.toggle(key: key, button: sender, content: previewContent(for: key))
        case let (.group(id), true):
            show(groupMenu(key: key, id: id), from: sender)
        }
    }

    /// Shows a menu the way macOS does for status items: attached below the icon, with the
    /// icon highlighted while it's open.
    private func show(_ menu: NSMenu, from button: NSStatusBarButton) {
        guard let key = button.identifier?.rawValue, let item = items[key] else { return }
        item.menu = menu
        button.performClick(nil)  // Tracks the menu until it closes.
        item.menu = nil  // Restore click actions for the next click.
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

        let badges = store.visibleBadges(monitor.badges)
        let badged = monitor.entries.filter { badges[$0.bundleID] != nil }
        menu.addItem(.sectionHeader(title: "Notifications"))
        if badged.isEmpty {
            let empty = NSMenuItem(title: monitor.isTrusted ? "You're all caught up" : "Waiting for permission", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for entry in badged {
                menu.addItem(appItem(bundleID: entry.bundleID, name: entry.name, badge: badges[entry.bundleID]))
            }
            menu.addItem(ClosureMenuItem("Mark All as Read") { [store, monitor] in
                store.markRead(badged.map(\.bundleID), badges: monitor.badges)
            })
        }

        menu.addItem(.separator())
        menu.addItem(historyItem("Notification History…", key: "main"))
        menu.addItem(ClosureMenuItem("Settings…", key: ",") { [openSettings] in openSettings(nil) })
        menu.addItem(ClosureMenuItem("Welcome Guide") { [openGuide] in openGuide() })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Quit BadgeBar", key: "q") { NSApp.terminate(nil) })
        return menu
    }

    /// Right-click menu for an app: its messages first, then actions.
    private func appMenu(
        key: String,
        bundleID: String,
        name: String,
        tracked: Bool
    ) -> NSMenu {
        let menu = NSMenu()
        let badge = store.visibleBadge(for: bundleID, monitor.badges[bundleID])
        // The header is the app itself, with its unread count, and opens it.
        menu.addItem(appItem(bundleID: bundleID, name: name, badge: badge))
        menu.addItem(.separator())

        let notes = recentNotes(for: [bundleID])
        addNotificationItems(notes, bundleID: bundleID, name: name, badge: badge, limit: Self.menuMessageLimit, to: menu, historyKey: key)

        menu.addItem(.separator())
        if badge != nil || !notes.isEmpty {
            menu.addItem(ClosureMenuItem("Mark as Read", symbol: "checkmark.circle") { [store, monitor] in
                store.markRead([bundleID], badges: monitor.badges)
            })
        }
        if tracked {
            menu.addItem(ClosureMenuItem("Customize…", symbol: "slider.horizontal.3") { [openSettings] in
                openSettings(.app(bundleID))
            })
            menu.addItem(ClosureMenuItem("Remove from Menu Bar", symbol: "minus.circle") { [store] in
                store.apps.removeAll { $0.bundleID == bundleID }
            })
        } else {
            menu.addItem(ClosureMenuItem("Keep in Menu Bar", symbol: "pin") { [store] in
                store.track(bundleID: bundleID, name: name)
            })
        }
        addBadgeBarItems(to: menu, historyKey: key)
        return menu
    }

    /// BadgeBar's own commands, at the bottom of every icon's menu.
    private func addBadgeBarItems(to menu: NSMenu, historyKey key: String) {
        menu.addItem(.separator())
        menu.addItem(historyItem("Notification History…", key: key))
        menu.addItem(ClosureMenuItem("Settings…", key: ",", symbol: "gearshape") { [openSettings] in openSettings(nil) })
        menu.addItem(ClosureMenuItem("Quit BadgeBar", key: "q", symbol: "power") { NSApp.terminate(nil) })
    }

    private func groupMenu(key: String, id: UUID) -> NSMenu {
        let menu = NSMenu()
        guard let group = store.groups.first(where: { $0.id == id }) else { return menu }
        let badges = store.visibleBadges(monitor.badges)
        let members = store.members(of: group)
        let notes = recentNotes(for: members.map(\.bundleID))

        for app in members {
            let badge = badges[app.bundleID]
            if menu.numberOfItems > 0 { menu.addItem(.separator()) }
            menu.addItem(appItem(bundleID: app.bundleID, name: app.name, badge: badge))
            let appNotes = notes.filter { $0.bundleID.caseInsensitiveCompare(app.bundleID) == .orderedSame }
            addNotificationItems(appNotes, bundleID: app.bundleID, name: app.name, badge: badge, limit: 3, to: menu, historyKey: key)
        }
        menu.addItem(.separator())
        if !badges.filter({ id in members.contains { $0.bundleID == id.key } }).isEmpty || !notes.isEmpty {
            menu.addItem(ClosureMenuItem("Mark All as Read", symbol: "checkmark.circle") { [store, monitor] in
                store.markRead(members.map(\.bundleID), badges: monitor.badges)
            })
        }
        menu.addItem(ClosureMenuItem("Customize Group…", symbol: "slider.horizontal.3") { [openSettings] in openSettings(.group(id)) })
        addBadgeBarItems(to: menu, historyKey: key)
        return menu
    }

    private static let menuMessageLimit = 6

    /// Recent, not-cleared notifications, or none if previews are off or not permitted.
    private func recentNotes(for bundleIDs: [String]) -> [DeliveredNotification] {
        guard store.general.showMessageContent, Permissions.hasFullDiskAccess else { return [] }
        return NotificationDatabase.recent(for: bundleIDs, limit: 60).filter(store.isVisible)
    }

    /// Adds one menu item per message (sender as the title, message as the subtitle), then a
    /// "Show All" item when there are more than fit.
    private func addNotificationItems(
        _ notes: [DeliveredNotification],
        bundleID: String,
        name: String,
        badge: Badge?,
        limit: Int,
        to menu: NSMenu,
        historyKey: String
    ) {
        guard store.general.showMessageContent else { return }
        guard Permissions.hasFullDiskAccess else {
            menu.addItem(ClosureMenuItem("Allow Full Disk Access to See Messages…") {
                Permissions.requestFullDiskAccess()
            })
            return
        }
        if notes.isEmpty {
            let empty = NSMenuItem(title: badge == nil ? "No new messages" : "Open \(name) to read new messages", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }

        let unread = badge?.count ?? 0
        for (index, note) in notes.prefix(limit).enumerated() {
            menu.addItem(messageItem(note, bundleID: bundleID, unread: index < unread))
        }
        let remaining = max(notes.count, unread) - min(notes.count, limit)
        if remaining > 0 {
            menu.addItem(historyItem("Show All Messages…", key: historyKey, symbol: "list.bullet"))
        }
    }

    /// Opens the notification preview under the menu's icon, including messages already read.
    private func historyItem(_ title: String, key: String, symbol: String = "clock.arrow.circlepath") -> NSMenuItem {
        ClosureMenuItem(title, symbol: symbol) { [weak self] in
            guard let self, let button = self.menuSource else { return }
            self.preview.toggle(
                key: key,
                button: button,
                content: self.previewContent(for: key, history: true)
            )
        }
    }

    private func messageItem(_ note: DeliveredNotification, bundleID: String, unread: Bool) -> NSMenuItem {
        NotificationMenuItem(note, icon: AppIcons.icon(for: bundleID), unread: unread) { AppIcons.open(bundleID) }
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

/// Forwards a status button's tracking area events to the controller.
@MainActor
private final class HoverTracker: NSResponder {
    let key: String
    weak var controller: StatusBarController?

    init(key: String, controller: StatusBarController) {
        self.key = key
        self.controller = controller
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func mouseEntered(with event: NSEvent) { controller?.pointer(enteredKey: key, inside: true) }
    override func mouseExited(with event: NSEvent) { controller?.pointer(enteredKey: key, inside: false) }
}

// TEMP-HOVERLOG: remove once hover is confirmed on macOS 27.
enum HoverLog {
    static func write(_ line: String) {
        let url = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/BadgeBar-hover.log")
        let data = Data("\(Date()) \(line)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); handle.write(data); try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}

/// NSMenuItem that runs a closure when chosen.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", symbol: String? = nil, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        target = self
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}

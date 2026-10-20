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
        var badge: Badge? = nil
        /// Identifies everything that affects how the item looks, so animation frames drawn
        /// for it can be reused until it changes.
        var look: AnyHashable? = nil
        /// Draws the item with an attention effect, for items with a badge.
        var effect: ((BadgeEffect, CGFloat) -> NSImage)? = nil
    }

    /// Extra width around each icon. None: macOS already spaces separate items apart.
    private static let itemPadding: CGFloat = 0

    private let store: Store
    private let monitor: BadgeMonitor
    private let openSettings: (SidebarItem?) -> Void
    private let openGuide: () -> Void
    /// Where the open menu came from, so its items can show a preview from the same icon.
    private var menuSource: NSStatusBarButton?
    /// Where that icon was clicked, in screen coordinates.
    private var menuClick: NSPoint?
    private let preview = PreviewPopover()
    private lazy var effects = BadgeEffects(
        draw: { [weak self] key, image in
            guard let item = self?.items[key], item.isVisible else { return }
            item.button?.image = image
        },
        appearance: { [weak self] key in self?.items[key]?.button?.effectiveAppearance }
    )

    private var items: [String: NSStatusItem] = [:]
    private var kinds: [String: Kind] = [:]
    /// The menu bar items that app and group items are shown in, under fixed autosave names.
    /// macOS remembers where each one sits (e.g. outside a menu bar hider like Hidden Bar), so
    /// arranging only changes which item each slot shows; slots are never renamed or re-added.
    /// macOS puts a new item left of the others, so higher numbers start further left.
    private var slots: [NSStatusItem] = []
    /// Slot numbers from left to right, as last seen on screen.
    private var slotOrder: [Int] = []
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
        Self.forgetRenamedItems()

        // @Published fires before the value changes, so hop to the next runloop turn
        // and coalesce bursts of changes into one rebuild.
        // Apps opening and quitting matter when icons hide for apps that aren't open.
        let workspace = NSWorkspace.shared.notificationCenter
        Publishers.Merge4(
            store.objectWillChange.map { _ in () },
            monitor.objectWillChange.map { _ in () },
            workspace.publisher(for: NSWorkspace.didLaunchApplicationNotification).map { _ in () },
            workspace.publisher(for: NSWorkspace.didTerminateApplicationNotification).map { _ in () }
        )
        .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
        .sink { [weak self] in self?.rebuild() }
        .store(in: &cancellables)

        rebuild()
        effects.isReady = true
        // Badges that were there at launch only play when they repeat; pick those up now.
        if store.general.repeatBadgeEffect { rebuild() }
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
        let running = store.general.hideWhenNotRunning ? AppIcons.runningBundleIDs() : []
        effects.effect = store.general.badgeEffect
        effects.repeats = store.general.repeatBadgeEffect
        var specs: [Spec] = []

        for app in store.apps where app.groupID == nil {
            let badge = badges[app.bundleID]
            let appearance = app.appearance.resolved(store.general)
            let icon = AppIcons.menuBarIcon(for: app)
            specs.append(Spec(
                key: "app.\(app.bundleID)",
                kind: .app(bundleID: app.bundleID, name: app.name, tracked: true),
                image: BadgeRenderer.image(icon: icon, badge: badge, appearance: appearance),
                tooltip: tooltip(app.name, badge),
                visible: store.shouldShow(badge: badge, appearance: appearance, bundleIDs: [app.bundleID], running: running),
                badge: badge,
                look: [AnyHashable(app), AnyHashable(appearance), AnyHashable(badge)],
                effect: badge.map { Self.effectRenderer(icon: icon, badge: $0, appearance: appearance) }
            ))
        }

        for group in store.groups {
            let members = store.members(of: group)
            let memberBadges = members.compactMap { badges[$0.bundleID] }
            let badge = Badge.combine(memberBadges)
            let appearance = group.appearance.resolved(store.general)
            let icon = AppIcons.menuBarIcon(for: group)
            specs.append(Spec(
                key: "group.\(group.id.uuidString)",
                kind: .group(group.id),
                image: BadgeRenderer.image(icon: icon, badge: badge, appearance: appearance),
                tooltip: tooltip(group.name, badge),
                visible: store.shouldShow(badge: badge, appearance: appearance, bundleIDs: members.map(\.bundleID), running: running),
                badge: badge,
                look: [AnyHashable(group), AnyHashable(appearance), AnyHashable(badge)],
                effect: badge.map { Self.effectRenderer(icon: icon, badge: $0, appearance: appearance) }
            ))
        }

        if store.general.autoShowBadgedApps {
            for entry in monitor.entries where !store.isTracked(entry.bundleID) {
                guard let badge = badges[entry.bundleID] else { continue }
                let icon = AppIcons.menuBarIcon(for: entry.bundleID)
                specs.append(Spec(
                    key: "auto.\(entry.bundleID)",
                    kind: .app(bundleID: entry.bundleID, name: entry.name, tracked: false),
                    image: BadgeRenderer.image(icon: icon, badge: badge, appearance: BadgeAppearance()),
                    tooltip: tooltip(entry.name, badge),
                    visible: true,
                    badge: badge,
                    look: [AnyHashable(entry.bundleID), AnyHashable(badge)],
                    effect: Self.effectRenderer(icon: icon, badge: badge, appearance: BadgeAppearance())
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

    /// Draws an item's animation frames. The icon is shrunk to menu bar size on first use,
    /// so items that never animate don't pay for it.
    private static func effectRenderer(
        icon: NSImage,
        badge: Badge,
        appearance: BadgeAppearance
    ) -> (BadgeEffect, CGFloat) -> NSImage {
        var small: NSImage?
        return { effect, phase in
            let icon = small ?? BadgeRenderer.rasterized(icon)
            small = icon
            return BadgeRenderer.image(icon: icon, badge: badge, appearance: appearance, effect: effect, phase: phase)
        }
    }

    private func applyItems(_ specs: [Spec]) {
        let wanted = Set(specs.map(\.key))
        for (key, item) in items where !wanted.contains(key) {
            if preview.anchorKey == key { preview.close() }
            // Slots are reused or removed in `assignSlots`.
            if !Self.isOrdered(key) { NSStatusBar.system.removeStatusItem(item) }
            items[key] = nil
            kinds[key] = nil
            effects.remove(key: key)
        }

        assignSlots(specs.map(\.key).filter(Self.isOrdered))

        // macOS places each new item to the left of the existing ones, so create right to left.
        for spec in specs.reversed() where items[spec.key] == nil {
            items[spec.key] = makeItem(key: spec.key, autosaveName: "BadgeBar.\(spec.key)")
        }

        for spec in specs {
            guard let item = items[spec.key] else { continue }
            kinds[spec.key] = spec.kind
            effects.update(key: spec.key, badge: spec.badge, look: spec.look, render: spec.effect)
            if !effects.isAnimating(spec.key) { item.button?.image = spec.image }
            // A fixed width that hugs the image. Variable-length items add generous padding on
            // both sides, which spreads several badge icons too far apart.
            item.length = ceil(spec.image.size.width) + Self.itemPadding
            item.button?.toolTip = spec.tooltip
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

    /// Shows app and group items in the menu bar slots, left to right in the given order.
    private func assignSlots(_ order: [String]) {
        while slots.count < order.count {
            slots.append(makeItem(key: "", autosaveName: "BadgeBar.slot.\(slots.count)"))
        }
        while slots.count > order.count, let slot = slots.popLast() {
            NSStatusBar.system.removeStatusItem(slot)
        }
        updateSlotOrder()

        for (key, index) in zip(order, slotOrder) {
            let slot = slots[index]
            guard items[key] !== slot else { continue }
            if preview.anchorKey == key { preview.close() }
            items[key] = slot
            slot.button?.identifier = NSUserInterfaceItemIdentifier(key)
            effects.redraw(key: key)
        }
    }

    /// Reads the slots' left-to-right order from the screen when macOS reports real, distinct
    /// positions. Otherwise (items hidden by a menu bar hider, or placeholder geometry) keeps
    /// the last known order, with new slots on the left, where macOS adds them.
    private func updateSlotOrder() {
        let frames = slots.map { $0.button?.window?.frame ?? .zero }
        if frames.allSatisfy({ $0.height > 0 }), Set(frames.map(\.minX)).count == frames.count {
            slotOrder = slots.indices.sorted { frames[$0].minX < frames[$1].minX }
        } else {
            let known = slotOrder.filter { $0 < slots.count }
            slotOrder = slots.indices.filter { !known.contains($0) }.reversed() + known
        }
    }

    /// Earlier versions re-added items under a new name each time they were arranged, which
    /// macOS treats as brand-new items and places at the far left, inside a menu bar hider's
    /// hidden section. Drops the settings macOS kept for all those old names.
    private static func forgetRenamedItems() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "statusItemGeneration") != nil else { return }
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("NSStatusItem") && (key.contains("BadgeBar.app.") || key.contains("BadgeBar.group.")) {
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: "statusItemGeneration")
    }

    private func makeItem(key: String, autosaveName: String) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // macOS remembers each item's spot by this name.
        item.autosaveName = autosaveName
        if let button = item.button {
            button.identifier = NSUserInterfaceItemIdentifier(key)
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
        }
        return item
    }

    private func tooltip(_ name: String, _ badge: Badge?) -> String {
        guard let badge else { return name }
        return badge.count == nil ? "\(name) — new activity" : "\(name) — \(badge.label)"
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
        let event = NSApp.currentEvent
        guard let key = sender.identifier?.rawValue else { return }
        guard let kind = kinds[key] else { return }
        let secondary = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if secondary { preview.close() }
        menuSource = sender
        menuClick = NSEvent.mouseLocation

        switch (kind, secondary) {
        case (.main, false) where monitor.isTrusted:
            preview.toggle(key: key, button: sender, click: menuClick, content: previewContent(for: key))
        case (.main, _):
            preview.close()
            show(mainMenu(), from: sender)
        case let (.app(bundleID, _, _), false):
            // Like a Dock icon: a click opens the app. Messages are a right-click away.
            preview.close()
            AppIcons.open(bundleID)
        case let (.app(bundleID, name, tracked), true):
            show(appMenu(key: key, bundleID: bundleID, name: name, tracked: tracked), from: sender)
        case (.group, false):
            // A group has no single app to open, so a click shows its messages.
            preview.toggle(key: key, button: sender, click: menuClick, content: previewContent(for: key))
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
                store.removeApp(bundleID)
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
                click: self.menuClick,
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

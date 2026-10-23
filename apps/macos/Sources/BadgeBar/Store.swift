import Foundation

/// Persists user configuration to UserDefaults as JSON.
@MainActor
final class Store: ObservableObject {
    @Published var apps: [TrackedApp] { didSet { save(apps, Keys.apps) } }
    @Published var groups: [AppGroup] { didSet { save(groups, Keys.groups) } }
    @Published var general: GeneralSettings { didSet { save(general, Keys.general) } }
    @Published private(set) var cleared: ClearedNotifications { didSet { save(cleared, Keys.cleared) } }

    private enum Keys {
        static let apps = "trackedApps"
        static let groups = "groups"
        static let general = "general"
        static let cleared = "clearedNotifications"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        apps = Self.load([TrackedApp].self, Keys.apps, defaults) ?? []
        groups = Self.load([AppGroup].self, Keys.groups, defaults) ?? []
        general = Self.load(GeneralSettings.self, Keys.general, defaults) ?? GeneralSettings()
        cleared = Self.load(ClearedNotifications.self, Keys.cleared, defaults) ?? ClearedNotifications()
        migrateEmptyBehavior()
        migrateSingleItem()
    }

    /// BadgeBar's own icon used to be on by default as a separate item. Its commands now live
    /// in every icon's menu, so turn it off once for existing setups.
    private func migrateSingleItem() {
        let key = "migratedSingleItem"
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        general.showMainIcon = false
    }

    /// Before the global nothing-new rule existed, every app stored "Dim" as its default.
    /// Turn those into "Use Default" once, so the new global rule applies to them.
    private func migrateEmptyBehavior() {
        let key = "migratedEmptyBehavior"
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        for i in apps.indices where apps[i].appearance.emptyBehavior == .dim {
            apps[i].appearance.emptyBehavior = .useDefault
        }
        for i in groups.indices where groups[i].appearance.emptyBehavior == .dim {
            groups[i].appearance.emptyBehavior = .useDefault
        }
    }

    // MARK: Clearing
    //
    // Notification Center's history belongs to macOS, so "clearing" hides notifications in
    // BadgeBar only. New notifications arriving afterwards still show up.

    func isVisible(_ note: DeliveredNotification) -> Bool {
        if cleared.ids.contains(note.id) { return false }
        if let before = cleared.before[note.bundleID.lowercased()], note.date <= before { return false }
        return true
    }

    func clear(_ bundleIDs: [String]) {
        let now = Date()
        for id in bundleIDs { cleared.before[id.lowercased()] = now }
    }

    /// Marks apps as read: hides their current notifications and badges until something new arrives.
    /// The apps themselves still consider the messages unread; macOS offers no way to change that.
    func markRead(_ bundleIDs: [String], badges: [String: Badge]) {
        clear(bundleIDs)
        for id in bundleIDs {
            if let badge = badges[id] { cleared.acknowledged[id.lowercased()] = badge.label }
        }
    }

    /// The badge to show for an app, or nil if the user already marked this count as read.
    func visibleBadge(for bundleID: String, _ badge: Badge?) -> Badge? {
        guard let badge, let read = cleared.acknowledged[bundleID.lowercased()] else { return badge }
        if read == badge.label { return nil }
        if let count = badge.count, let readCount = Int(read), count <= readCount { return nil }
        return badge
    }

    func visibleBadges(_ badges: [String: Badge]) -> [String: Badge] {
        badges.filter { visibleBadge(for: $0.key, $0.value) != nil }
    }

    /// Keeps "read" marks in step with the apps, so anything new shows up again:
    /// - the badge went away: forget the mark;
    /// - the count dropped (messages read in the app): lower the mark, so the next message
    ///   counts as new instead of hiding until the count passes the old number;
    /// - a notification arrived after marking as read: forget the mark. This is what catches
    ///   new messages for apps whose badge has no number.
    func refreshAcknowledged(current badges: [String: Badge], latestNotification: (String) -> Date?) {
        let live = Dictionary(badges.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
        var acknowledged = cleared.acknowledged
        for (id, read) in cleared.acknowledged {
            guard let badge = live[id] else {
                acknowledged[id] = nil
                continue
            }
            if let count = badge.count, let readCount = Int(read), count < readCount {
                acknowledged[id] = badge.label
            }
            if let markedAt = cleared.before[id], let latest = latestNotification(id), latest > markedAt {
                acknowledged[id] = nil
            }
        }
        if acknowledged != cleared.acknowledged { cleared.acknowledged = acknowledged }
    }

    func dismiss(_ note: DeliveredNotification) {
        cleared.ids.insert(note.id)
        // Keep the set from growing forever.
        if cleared.ids.count > 500 { cleared.ids = Set(cleared.ids.sorted().suffix(300)) }
    }

    func isTracked(_ bundleID: String) -> Bool {
        apps.contains { $0.bundleID == bundleID }
    }

    func track(bundleID: String, name: String) {
        guard !isTracked(bundleID) else { return }
        apps.append(TrackedApp(bundleID: bundleID, name: name))
    }

    /// Adds several apps in a stable (alphabetical) order and returns the IDs actually added.
    @discardableResult
    func track(bundleIDs: Set<String>, names: [String: String], style: BadgeStyle? = nil) -> [String] {
        let new = bundleIDs
            .filter { !isTracked($0) }
            .sorted { (names[$0] ?? $0).localizedStandardCompare(names[$1] ?? $1) == .orderedAscending }
        apps += new.map { id in
            var app = TrackedApp(bundleID: id, name: names[id] ?? id)
            if let style { app.appearance.style = style }
            return app
        }
        return new
    }

    /// Reorders apps and groups to match menu bar keys ("app.<id>", "group.<uuid>"), left to
    /// right. Items not listed (hidden ones) keep their places. Returns whether anything moved.
    @discardableResult
    func reorder(byKeys keys: [String]) -> Bool {
        func arranged<T>(_ list: [T], key: (T) -> String) -> [T] {
            let rank = Dictionary(uniqueKeysWithValues: keys.enumerated().map { ($1, $0) })
            let placed = list.filter { rank[key($0)] != nil }.sorted { rank[key($0)]! < rank[key($1)]! }
            var next = placed.makeIterator()
            return list.map { rank[key($0)] != nil ? next.next()! : $0 }
        }
        let newApps = arranged(apps) { "app.\($0.bundleID)" }
        let newGroups = arranged(groups) { "group.\($0.id.uuidString)" }
        let changed = newApps.map(\.bundleID) != apps.map(\.bundleID) || newGroups.map(\.id) != groups.map(\.id)
        if changed {
            apps = newApps
            groups = newGroups
        }
        return changed
    }

    /// Adds a group with a name no other group uses yet ("New Group", "New Group 2", …).
    func addGroup() -> AppGroup {
        let names = Set(groups.map(\.name))
        let name = (1...).lazy.map { $0 == 1 ? "New Group" : "New Group \($0)" }.first { !names.contains($0) }!
        let group = AppGroup(name: name)
        groups.append(group)
        return group
    }

    func members(of group: AppGroup) -> [TrackedApp] {
        apps.filter { $0.groupID == group.id }
    }

    /// Whether an icon belongs in the menu bar right now. A badge always shows; otherwise the
    /// icon follows its "nothing new" setting and, if asked, hides while none of its apps is open.
    func shouldShow(badge: Badge?, appearance: BadgeAppearance, bundleIDs: [String], running: Set<String>) -> Bool {
        if badge != nil { return true }
        if appearance.emptyBehavior == .hide { return false }
        guard general.hideWhenNotRunning else { return true }
        return bundleIDs.contains { running.contains($0.lowercased()) }
    }

    /// Takes an app out of the menu bar, along with its copied custom image and saved history.
    func removeApp(_ bundleID: String) {
        AppIcons.removeCustomIcon(apps.first { $0.bundleID == bundleID }?.customIconPath)
        apps.removeAll { $0.bundleID == bundleID }
        NotificationHistory.shared.clear([bundleID])
    }

    func deleteGroup(_ id: UUID) {
        AppIcons.removeCustomIcon(groups.first { $0.id == id }?.customIconPath)
        groups.removeAll { $0.id == id }
        for i in apps.indices where apps[i].groupID == id {
            apps[i].groupID = nil
        }
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String, _ defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

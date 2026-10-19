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

    func members(of group: AppGroup) -> [TrackedApp] {
        apps.filter { $0.groupID == group.id }
    }

    func deleteGroup(_ id: UUID) {
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

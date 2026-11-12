import AppKit
import Combine

/// Shares unread counts with other tools, such as SketchyBar, Raycast, Shortcuts and shell
/// scripts, while "Share unread counts" is on.
///
/// BadgeBar keeps `badges.json` in its Application Support folder up to date, and posts a
/// distributed notification each time it changes, so listeners don't need to poll. The file
/// holds counts only, never message text. It's deleted, with a notification, when sharing is
/// turned off, when BadgeBar loses access to the Dock and when it quits.
@MainActor
final class BadgeExport {
    /// Posted after the file changes. Carries no data; listeners read the file.
    static let changedNotification = Notification.Name("io.github.hk-vk.badgebar.changed")

    static var fileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("BadgeBar/badges.json")
    }

    /// One app in the file. Field names are a public format: add fields, don't rename them.
    struct App: Codable, Equatable {
        var bundleID: String
        var name: String
        /// The badge text as the Dock shows it, e.g. "3" or "•". Nil when there's nothing new.
        var label: String?
        /// The number in the badge, or nil for a badge without one.
        var count: Int?
        var running: Bool
        /// Whether the user added the app to BadgeBar, as opposed to an app that only has a badge.
        var tracked: Bool
        /// The name of the BadgeBar group the app is in, if any.
        var group: String?
    }

    struct Snapshot: Codable {
        var version = 1
        var updatedAt: Date
        /// The sum of every numeric badge.
        var total: Int
        var apps: [App]
    }

    private let store: Store
    private let monitor: BadgeMonitor
    /// What the file holds now, or nil when there's no file.
    private var lastApps: [App]?
    private var cancellables: Set<AnyCancellable> = []

    init(store: Store, monitor: BadgeMonitor) {
        self.store = store
        self.monitor = monitor
        // @Published fires before the value changes, so wait a moment and coalesce bursts.
        // The main queue, unlike the run loop's default mode, keeps going while a menu is open.
        let workspace = NSWorkspace.shared.notificationCenter
        Publishers.Merge4(
            store.objectWillChange.map { _ in () },
            monitor.objectWillChange.map { _ in () },
            workspace.publisher(for: NSWorkspace.didLaunchApplicationNotification).map { _ in () },
            workspace.publisher(for: NSWorkspace.didTerminateApplicationNotification).map { _ in () }
        )
        .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
        .sink { [weak self] in self?.update() }
        .store(in: &cancellables)

        // A file left behind by a crash would hold old counts.
        if let url = Self.fileURL, FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
            Self.postChanged()
        }
        update()
    }

    func update() {
        // Without access to the Dock the counts would go stale, so remove the file instead.
        guard store.general.shareCounts, monitor.isTrusted else {
            stop()
            return
        }
        guard let url = Self.fileURL else { return }

        let names = Dictionary(monitor.entries.map { ($0.bundleID, $0.name) }, uniquingKeysWith: { a, _ in a })
        let apps = Self.apps(
            tracked: store.apps,
            groups: store.groups,
            badges: store.visibleBadges(monitor.badges),
            names: names,
            running: AppIcons.runningBundleIDs()
        )
        // Only write when something changed; the Dock is read every second or so.
        guard apps != lastApps else { return }

        let snapshot = Snapshot(updatedAt: Date(), total: apps.compactMap(\.count).reduce(0, +), apps: apps)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
        lastApps = apps
        Self.postChanged()
    }

    /// Removes the file, and tells listeners so they stop showing its counts.
    func stop() {
        guard lastApps != nil else { return }
        lastApps = nil
        if let url = Self.fileURL { try? FileManager.default.removeItem(at: url) }
        Self.postChanged()
    }

    private static func postChanged() {
        DistributedNotificationCenter.default().postNotificationName(
            changedNotification, object: nil, userInfo: nil, deliverImmediately: true
        )
    }

    /// The apps to list: every added app in menu bar order, then other apps that have a badge,
    /// by name. `running` holds lowercased bundle IDs.
    nonisolated static func apps(
        tracked: [TrackedApp],
        groups: [AppGroup],
        badges: [String: Badge],
        names: [String: String],
        running: Set<String>
    ) -> [App] {
        let groupNames = Dictionary(groups.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let trackedIDs = Set(tracked.map { $0.bundleID.lowercased() })
        // Saved and Dock bundle IDs can differ in letter case.
        let byLowercased = Dictionary(badges.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })

        var result = tracked.map { app in
            let badge = byLowercased[app.bundleID.lowercased()]
            return App(
                bundleID: app.bundleID,
                name: app.name,
                label: badge?.label,
                count: badge?.count,
                running: running.contains(app.bundleID.lowercased()),
                tracked: true,
                group: app.groupID.flatMap { groupNames[$0] }
            )
        }
        let others = badges
            .filter { !trackedIDs.contains($0.key.lowercased()) }
            .map { id, badge in
                App(
                    bundleID: id,
                    name: names[id] ?? id,
                    label: badge.label,
                    count: badge.count,
                    running: running.contains(id.lowercased()),
                    tracked: false,
                    group: nil
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        result += others
        return result
    }
}

/// An action requested through a `badgebar://` link, e.g. `badgebar://open?app=com.apple.mail`.
///
/// Any app or web page can open these links, so they only do what clicking BadgeBar's icons
/// can do: open an app BadgeBar shows, mark messages as read, or show Settings.
enum URLCommand: Equatable {
    /// Opens an app BadgeBar shows, like clicking its icon.
    case open(bundleID: String)
    /// Marks the given app's messages as read, or every app's when nil.
    case markRead(bundleID: String?)
    case settings

    init?(_ url: URL) {
        guard url.scheme?.lowercased() == "badgebar",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let app = components.queryItems?.first { $0.name == "app" }?.value
            .flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        switch components.host?.lowercased() {
        case "open":
            guard let app else { return nil }
            self = .open(bundleID: app)
        case "mark-read":
            self = .markRead(bundleID: app)
        case "settings":
            self = .settings
        default:
            return nil
        }
    }
}

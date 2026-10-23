import Foundation

/// BadgeBar's own copy of recent notifications.
///
/// Notification Center deletes a notification as soon as it's cleared, or when the app
/// withdraws it (Slack does once a message is read), so its database alone can't serve as a
/// history. This copies new records every few seconds and keeps the last few per app, on disk.
@MainActor
final class NotificationHistory {
    static let shared = NotificationHistory()

    /// How many notifications to keep per app.
    var limit = GeneralSettings().historyLimit {
        didSet { if limit != oldValue { prune() } }
    }

    /// Off while message text is hidden, so nothing new is copied.
    var isEnabled = true

    /// Newest first.
    private(set) var notes: [DeliveredNotification] = []
    private var lastRecordID: Int64 = 0
    private var timer: Timer?

    private struct Saved: Codable {
        var notes: [DeliveredNotification]
        var lastRecordID: Int64
    }

    private static var fileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("BadgeBar/NotificationHistory.json")
    }

    private init() {
        guard let url = Self.fileURL, let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        notes = saved.notes
        lastRecordID = saved.lastRecordID
    }

    func start(interval: TimeInterval = 3) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync() }
        }
        timer?.tolerance = interval * 0.3
        sync()
    }

    /// Copies notifications delivered since the last sync.
    func sync() {
        guard isEnabled, Permissions.hasFullDiskAccess else { return }
        var (added, maxID) = NotificationDatabase.added(after: lastRecordID, limit: 2000)
        guard let maxID else { return }
        // Record IDs went backwards: Notification Center's database was reset. Start over from it.
        if maxID < lastRecordID {
            (added, _) = NotificationDatabase.added(after: 0, limit: 2000)
        }
        let changed = !added.isEmpty || maxID != lastRecordID
        lastRecordID = maxID
        guard changed else { return }
        let known = Set(notes.map(Key.init))
        notes = (notes + added.filter { !known.contains(Key($0)) }).sorted { $0.date > $1.date }
        prune()
    }

    /// Kept notifications for the given apps (or all apps when nil), newest first.
    func notes(for bundleIDs: [String]?) -> [DeliveredNotification] {
        guard let bundleIDs else { return notes }
        let ids = Set(bundleIDs.map { $0.lowercased() })
        return notes.filter { ids.contains($0.bundleID.lowercased()) }
    }

    func clear() {
        notes = []
        save()
    }

    private func prune() {
        var counts: [String: Int] = [:]
        notes = notes.filter { note in
            let app = note.bundleID.lowercased()
            counts[app, default: 0] += 1
            return counts[app]! <= limit
        }
        save()
    }

    private func save() {
        guard let url = Self.fileURL,
              let data = try? JSONEncoder().encode(Saved(notes: notes, lastRecordID: lastRecordID)) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// Record IDs restart if the database is reset, so pair them with the delivery date.
    private struct Key: Hashable {
        let id: Int64
        let date: Date
        init(_ note: DeliveredNotification) { id = note.id; date = note.date }
    }
}

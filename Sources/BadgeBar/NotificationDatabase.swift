import Foundation
import SQLite3

/// A notification delivered by an app, as recorded by Notification Center.
struct DeliveredNotification: Identifiable, Hashable {
    let id: Int64
    let bundleID: String
    let title: String
    let subtitle: String
    let body: String
    let date: Date
}

/// Reads recent notifications from Notification Center's SQLite database.
///
/// macOS keeps every delivered notification in `group.com.apple.usernoted/db2/db`. The file
/// is protected by TCC, so reading it requires Full Disk Access. Without it, previews fall
/// back to showing just the badge count.
enum NotificationDatabase {
    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db")
    }

    static var isReadable: Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        try? handle.close()
        return true
    }

    /// The most recent notifications for the given apps (or all apps when nil), newest first.
    static func recent(for bundleIDs: [String]?, limit: Int = 6) -> [DeliveredNotification] {
        if let bundleIDs, bundleIDs.isEmpty { return [] }
        let filter = bundleIDs ?? []

        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return []
        }
        defer { sqlite3_close(db) }

        let placeholders = Array(repeating: "?", count: filter.count).joined(separator: ",")
        let sql = """
            SELECT r.rec_id, a.identifier, r.data, r.delivered_date
            FROM record r JOIN app a ON a.app_id = r.app_id
            \(bundleIDs == nil ? "" : "WHERE lower(a.identifier) IN (\(placeholders))")
            ORDER BY r.delivered_date DESC
            LIMIT ?
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, id) in filter.enumerated() {
            sqlite3_bind_text(statement, Int32(i + 1), id.lowercased(), -1, transient)
        }
        sqlite3_bind_int(statement, Int32(filter.count + 1), Int32(limit))

        // Map the database's (often lowercased) identifiers back to the caller's spelling.
        let canonical = Dictionary(filter.map { ($0.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })

        var results: [DeliveredNotification] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let recID = sqlite3_column_int64(statement, 0)
            let identifier = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let delivered = sqlite3_column_double(statement, 3)
            guard
                let blob = sqlite3_column_blob(statement, 2),
                case let size = Int(sqlite3_column_bytes(statement, 2)), size > 0,
                let plist = try? PropertyListSerialization.propertyList(
                    from: Data(bytes: blob, count: size), format: nil
                ) as? [String: Any],
                let request = plist["req"] as? [String: Any]
            else { continue }

            let title = request["titl"] as? String ?? ""
            let subtitle = request["subt"] as? String ?? ""
            let body = request["body"] as? String ?? ""
            guard !(title.isEmpty && body.isEmpty) else { continue }

            results.append(DeliveredNotification(
                id: recID,
                bundleID: canonical[identifier.lowercased()] ?? identifier,
                title: title,
                subtitle: subtitle,
                body: body,
                date: Date(timeIntervalSinceReferenceDate: delivered)
            ))
        }
        return results
    }
}

import Foundation
import SQLite3

/// A notification delivered by an app, as recorded by Notification Center.
struct DeliveredNotification: Identifiable, Hashable, Codable {
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
        query(for: bundleIDs, after: nil, limit: limit).notes
    }

    /// Notifications recorded after `recordID`, newest first, plus the highest record ID in the
    /// database (nil if it couldn't be read). macOS deletes records once they're cleared or the
    /// app withdraws them, so `NotificationHistory` uses this to keep its own copy.
    static func added(after recordID: Int64, limit: Int) -> (notes: [DeliveredNotification], maxID: Int64?) {
        query(for: nil, after: recordID, limit: limit)
    }

    private static func query(for bundleIDs: [String]?, after recordID: Int64?, limit: Int) -> (notes: [DeliveredNotification], maxID: Int64?) {
        if let bundleIDs, bundleIDs.isEmpty { return ([], nil) }
        let filter = bundleIDs ?? []

        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return ([], nil)
        }
        defer { sqlite3_close(db) }

        var conditions: [String] = []
        if bundleIDs != nil {
            conditions.append("lower(a.identifier) IN (\(Array(repeating: "?", count: filter.count).joined(separator: ",")))")
        }
        if recordID != nil { conditions.append("r.rec_id > ?") }
        let sql = """
            SELECT r.rec_id, a.identifier, r.data, r.delivered_date, (SELECT max(rec_id) FROM record)
            FROM record r JOIN app a ON a.app_id = r.app_id
            \(conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND "))
            ORDER BY r.delivered_date DESC
            LIMIT ?
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return ([], nil) }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var index: Int32 = 1
        for id in filter {
            sqlite3_bind_text(statement, index, id.lowercased(), -1, transient)
            index += 1
        }
        if let recordID {
            sqlite3_bind_int64(statement, index, recordID)
            index += 1
        }
        sqlite3_bind_int(statement, index, Int32(limit))

        // Map the database's (often lowercased) identifiers back to the caller's spelling.
        let canonical = Dictionary(filter.map { ($0.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })

        var results: [DeliveredNotification] = []
        var maxID: Int64?
        while sqlite3_step(statement) == SQLITE_ROW {
            maxID = sqlite3_column_int64(statement, 4)
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
        // No new rows: still learn the current highest ID, so a reset database is noticed.
        if maxID == nil, recordID != nil {
            var max: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT max(rec_id) FROM record", -1, &max, nil) == SQLITE_OK,
               sqlite3_step(max) == SQLITE_ROW {
                maxID = sqlite3_column_int64(max, 0)
            }
            sqlite3_finalize(max)
        }
        return (results, maxID)
    }
}

import AppKit
import SQLite3

/// One notification from another app (Messages, WhatsApp, Mail, Slack...).
struct NotchNote: Equatable, Identifiable {
    let id: Int64
    let bundle: String
    let appName: String
    let title: String
    let subtitle: String
    let body: String
    let date: Date
}

/// Reads new notifications from macOS's Notification Center database.
/// macOS has no public API for other apps' notifications, so this needs
/// Full Disk Access (System Settings > Privacy & Security > Full Disk Access).
final class NotificationReader {
    enum Status: Equatable { case unknown, ok, needsAccess, notFound }

    private(set) var status: Status = .unknown
    private var lastID: Int64 = -1
    private(set) var dbPath: String?

    static func candidatePaths() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var out = [home + "/Library/Group Containers/group.com.apple.usernoted/db2/db"]
        var buf = [CChar](repeating: 0, count: 1024)
        if confstr(_CS_DARWIN_USER_DIR, &buf, buf.count) > 0 {
            let dir = String(cString: buf)
            out.append(dir + "com.apple.notificationcenter/db2/db")
        }
        return out
    }

    /// Returns notifications that arrived since the last call.
    /// The first successful call only records where we are, so old ones aren't replayed.
    func poll() -> [NotchNote] {
        let fm = FileManager.default
        guard let path = NotificationReader.candidatePaths().first(where: { fm.fileExists(atPath: $0) }) else {
            // The Group Containers folder is hidden from apps without Full Disk Access.
            status = fm.isReadableFile(atPath: NotificationReader.candidatePaths()[0]) ? .notFound : .needsAccess
            return []
        }
        dbPath = path
        var db: OpaquePointer?
        let uri = "file:" + path + "?mode=ro"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK, let db else {
            status = .needsAccess
            if let db { sqlite3_close(db) }
            return []
        }
        defer { sqlite3_close(db) }

        if lastID < 0 {
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT IFNULL(MAX(rec_id), 0) FROM record", -1, &st, nil) == SQLITE_OK else {
                status = .needsAccess
                return []
            }
            defer { sqlite3_finalize(st) }
            if sqlite3_step(st) == SQLITE_ROW {
                lastID = sqlite3_column_int64(st, 0)
                status = .ok
            } else {
                status = .needsAccess
            }
            return []
        }

        let sql = """
            SELECT r.rec_id, IFNULL(a.identifier, ''), r.data
            FROM record r LEFT JOIN app a ON r.app_id = a.app_id
            WHERE r.rec_id > ? ORDER BY r.rec_id ASC LIMIT 20
            """
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else {
            status = .needsAccess
            return []
        }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_int64(st, 1, lastID)
        status = .ok

        var out: [NotchNote] = []
        while sqlite3_step(st) == SQLITE_ROW {
            let id = sqlite3_column_int64(st, 0)
            lastID = max(lastID, id)
            let bundle = sqlite3_column_text(st, 1).map { String(cString: $0) } ?? ""
            guard let blob = sqlite3_column_blob(st, 2) else { continue }
            let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(st, 2)))
            if let note = NotificationReader.parse(id: id, bundle: bundle, data: data) {
                out.append(note)
            }
        }
        return out
    }

    static func parse(id: Int64, bundle: String, data: Data) -> NotchNote? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { return nil }
        let req = plist["req"] as? [String: Any] ?? [:]
        let title = (req["titl"] as? String) ?? ""
        let subtitle = (req["subt"] as? String) ?? ""
        let body = (req["body"] as? String) ?? ""
        if title.isEmpty && body.isEmpty { return nil }
        let b = bundle.isEmpty ? (plist["app"] as? String ?? "") : bundle
        var date = Date()
        if let t = plist["date"] as? Double { date = Date(timeIntervalSinceReferenceDate: t) }
        return NotchNote(id: id, bundle: b, appName: appName(for: b), title: title,
                         subtitle: subtitle, body: body, date: date)
    }

    static func appName(for bundle: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundle.split(separator: ".").last.map(String.init)?.capitalized ?? "Notification"
    }

    static func icon(for bundle: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}

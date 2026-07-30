import Foundation
import SQLite3
import AppKit

struct CaptureHistoryEntry: Identifiable, Equatable {
    var id: UUID
    var createdAt: Date
    var kind: CaptureKind
    var sourceApp: String?
    var sourceWindow: String?
    var displayID: UInt32?
    var width: Int
    var height: Int
    var filePath: String?
    var thumbnailPath: String?
    var wasCopied: Bool
    var wasEdited: Bool
    var pinned: Bool
    var title: String?
    var tags: [String]
}

@MainActor
final class CaptureHistoryRepository: ObservableObject {
    @Published private(set) var entries: [CaptureHistoryEntry] = []
    private var db: OpaquePointer?
    private let dir: URL

    init() {
        dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ScreenForge/History", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("images"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("thumbs"), withIntermediateDirectories: true)
    }

    func open() {
        let path = dir.appendingPathComponent("history.sqlite").path
        if sqlite3_open(path, &db) != SQLITE_OK {
            DiagnosticLog.shared.error("history.db.open.failed")
            return
        }
        let sql = """
        CREATE TABLE IF NOT EXISTS captures (
            id TEXT PRIMARY KEY,
            created_at REAL,
            kind TEXT,
            source_app TEXT,
            source_window TEXT,
            display_id INTEGER,
            width INTEGER,
            height INTEGER,
            file_path TEXT,
            thumb_path TEXT,
            was_copied INTEGER,
            was_edited INTEGER,
            pinned INTEGER,
            title TEXT,
            tags TEXT
        );
        """
        sqlite3_exec(db, sql, nil, nil, nil)
        reload()
    }

    func close() {
        if let db { sqlite3_close(db) }
        db = nil
    }

    func storeFullImage(_ image: CGImage, id: UUID) -> URL? {
        let url = dir.appendingPathComponent("images/\(id.uuidString).png")
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        try? data.write(to: url, options: .atomic)
        return url
    }

    func insert(_ entry: CaptureHistoryEntry) {
        guard let db else { return }
        let sql = "INSERT OR REPLACE INTO captures VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, entry)
        sqlite3_step(stmt)
        reload()
    }

    func latest() -> CaptureHistoryEntry? { entries.first }

    /// Docs / tests only — replace the in-memory list without touching the database.
    func replaceEntriesForDocs(_ entries: [CaptureHistoryEntry]) {
        self.entries = entries
    }

    func reloadFromDisk() {
        reload()
    }

    func delete(_ id: UUID) {
        guard let db else { return }
        if let entry = entries.first(where: { $0.id == id }) {
            if let p = entry.filePath { try? FileManager.default.removeItem(atPath: p) }
            if let p = entry.thumbnailPath { try? FileManager.default.removeItem(atPath: p) }
        }
        let sql = "DELETE FROM captures WHERE id=?;"
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        sqlite3_bind_text(stmt, 1, (id.uuidString as NSString).utf8String, -1, nil)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        reload()
    }

    func setPinned(_ id: UUID, pinned: Bool) {
        guard let db else { return }
        let sql = "UPDATE captures SET pinned=? WHERE id=?;"
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        sqlite3_bind_int(stmt, 1, pinned ? 1 : 0)
        sqlite3_bind_text(stmt, 2, (id.uuidString as NSString).utf8String, -1, nil)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        reload()
    }

    func rename(_ id: UUID, title: String) {
        guard let db else { return }
        let sql = "UPDATE captures SET title=? WHERE id=?;"
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        sqlite3_bind_text(stmt, 1, (title as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (id.uuidString as NSString).utf8String, -1, nil)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        reload()
    }

    func enforceRetention(unlimited: Bool, maxCount: Int, maxDays: Int) {
        guard !unlimited else { return }
        let cutoff = Date().addingTimeInterval(-Double(maxDays) * 86400)
        for e in entries where !e.pinned {
            if e.createdAt < cutoff {
                delete(e.id)
            }
        }
        let unpinned = entries.filter { !$0.pinned }
        if unpinned.count > maxCount {
            for e in unpinned.suffix(from: maxCount) {
                delete(e.id)
            }
        }
    }

    func image(for entry: CaptureHistoryEntry) -> CGImage? {
        guard let path = entry.filePath else { return nil }
        return NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private func reload() {
        guard let db else { return }
        let sql = "SELECT * FROM captures ORDER BY created_at DESC;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        var result: [CaptureHistoryEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(read(stmt))
        }
        entries = result
    }

    private func bind(_ stmt: OpaquePointer?, _ e: CaptureHistoryEntry) {
        sqlite3_bind_text(stmt, 1, (e.id.uuidString as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 2, e.createdAt.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 3, (e.kind.rawValue as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 4, ((e.sourceApp ?? "") as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 5, ((e.sourceWindow ?? "") as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 6, Int32(e.displayID ?? 0))
        sqlite3_bind_int(stmt, 7, Int32(e.width))
        sqlite3_bind_int(stmt, 8, Int32(e.height))
        sqlite3_bind_text(stmt, 9, ((e.filePath ?? "") as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 10, ((e.thumbnailPath ?? "") as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 11, e.wasCopied ? 1 : 0)
        sqlite3_bind_int(stmt, 12, e.wasEdited ? 1 : 0)
        sqlite3_bind_int(stmt, 13, e.pinned ? 1 : 0)
        sqlite3_bind_text(stmt, 14, ((e.title ?? "") as NSString).utf8String, -1, nil)
        let tags = e.tags.joined(separator: ",")
        sqlite3_bind_text(stmt, 15, (tags as NSString).utf8String, -1, nil)
    }

    private func read(_ stmt: OpaquePointer?) -> CaptureHistoryEntry {
        func text(_ i: Int32) -> String? {
            guard let c = sqlite3_column_text(stmt, i) else { return nil }
            let s = String(cString: c)
            return s.isEmpty ? nil : s
        }
        return CaptureHistoryEntry(
            id: UUID(uuidString: text(0) ?? "") ?? UUID(),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
            kind: CaptureKind(rawValue: text(2) ?? "region") ?? .region,
            sourceApp: text(3),
            sourceWindow: text(4),
            displayID: UInt32(sqlite3_column_int(stmt, 5)),
            width: Int(sqlite3_column_int(stmt, 6)),
            height: Int(sqlite3_column_int(stmt, 7)),
            filePath: text(8),
            thumbnailPath: text(9),
            wasCopied: sqlite3_column_int(stmt, 10) != 0,
            wasEdited: sqlite3_column_int(stmt, 11) != 0,
            pinned: sqlite3_column_int(stmt, 12) != 0,
            title: text(13),
            tags: (text(14) ?? "").split(separator: ",").map(String.init)
        )
    }
}

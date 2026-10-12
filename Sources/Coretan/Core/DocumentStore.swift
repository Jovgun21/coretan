import Foundation
import SQLite3

/// Local-first persistence: metadata in SQLite, ink blobs and assets in per-notebook
/// bundles so a whole notebook is a folder you can copy.
///
/// Layout: Documents/Coretan/<notebookID>/meta.json, drawing.data, pages/*.ctnk, assets/
final class DocumentStore: ObservableObject {
    static let shared = DocumentStore()
    private var db: OpaquePointer?
    private let fm = FileManager.default

    var rootURL: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Coretan", isDirectory: true)
    }

    private init() { openDB() }

    private func openDB() {
        try? fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let path = rootURL.appendingPathComponent("coretan.sqlite").path
        guard sqlite3_open(path, &db) == SQLITE_OK else { db = nil; return }
        exec("""
        CREATE TABLE IF NOT EXISTS notebooks(id TEXT PRIMARY KEY, json TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS folders(id TEXT PRIMARY KEY, json TEXT NOT NULL);
        CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(id UNINDEXED, content);
        """)
    }

    private func exec(_ sql: String) {
        var err: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, sql, nil, nil, &err)
    }

    // MARK: Notebooks

    @discardableResult
    func listNotebooks() -> [NotebookMeta] {
        guard let db else { return [] }
        var out: [NotebookMeta] = []
        var st: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT json FROM notebooks", -1, &st, nil)
        defer { sqlite3_finalize(st) }
        while sqlite3_step(st) == SQLITE_ROW,
              let c = sqlite3_column_text(st, 0) {
            let s = String(cString: c)
            if let m = try? JSONDecoder().decode(NotebookMeta.self, from: Data(s.utf8)) {
                out.append(m)
            }
        }
        return out.sorted { $0.updatedAt > $1.updatedAt }
    }

    func saveNotebook(_ nb: NotebookMeta) {
        guard let db,
              let j = try? JSONEncoder().encode(nb),
              let s = String(data: j, encoding: .utf8)
        else { return }
        var st: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO notebooks(id, json) VALUES(?1, ?2)", -1, &st, nil)
        defer { sqlite3_finalize(st) }
        sqlite3_bind_text(st, 1, nb.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(st, 2, s, -1, SQLITE_TRANSIENT)
        sqlite3_step(st)
        // mirror meta.json inside the bundle for portability
        let dir = bundleURL(for: nb.id)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try? j.write(to: dir.appendingPathComponent("meta.json"))
    }

    func deleteNotebook(_ id: UUID) {
        guard let db else { return }
        var st: OpaquePointer?
        sqlite3_prepare_v2(db, "DELETE FROM notebooks WHERE id = ?1", -1, &st, nil)
        sqlite3_bind_text(st, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_step(st); sqlite3_finalize(st)
        try? fm.removeItem(at: bundleURL(for: id))
    }

    func bundleURL(for notebookID: UUID) -> URL {
        rootURL.appendingPathComponent(notebookID.uuidString, isDirectory: true)
    }
}

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

import Foundation
import UIKit
import SQLite3
import Vision

/// Full-text index over typed text, PDF text and recognised handwriting.
/// Handwriting OCR runs through Vision and its result is linked back to the
/// stroke bounds, so a search hit can highlight where the word sits on the page.
final class SearchIndex {
    static let shared = SearchIndex()
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "coretan.search", qos: .utility)

    struct Hit {
        var pageID: UUID
        var notebookID: UUID
        var snippet: String
        var rects: [CGRect]
    }

    private init() {
        let url = DocumentStore.shared.rootURL.appendingPathComponent("search.sqlite")
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { db = nil; return }
        exec("""
        CREATE VIRTUAL TABLE IF NOT EXISTS page_fts USING fts5(page_id UNINDEXED, notebook_id UNINDEXED, text);
        CREATE TABLE IF NOT EXISTS page_text(page_id TEXT PRIMARY KEY, notebook_id TEXT, text TEXT, rects TEXT);
        """)
    }

    private func exec(_ sql: String) {
        var e: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, sql, nil, nil, &e)
    }

    func index(pageID: UUID, notebookID: UUID, strokes: [InkStroke]) {
        queue.async { [weak self] in
            guard let self else { return }
            let text = Self.typedText(in: strokes)
            guard !text.isEmpty else { return }
            self.replace(pageID: pageID, notebookID: notebookID, text: text, rects: [])
        }
    }

    func indexRecognized(pageID: UUID, notebookID: UUID, text: String, rects: [CGRect]) {
        queue.async { [weak self] in
            self?.replace(pageID: pageID, notebookID: notebookID, text: text, rects: rects)
        }
    }

    private func replace(pageID: UUID, notebookID: UUID, text: String, rects: [CGRect]) {
        guard let db else { return }
        var del: OpaquePointer?
        sqlite3_prepare_v2(db, "DELETE FROM page_fts WHERE page_id = ?1", -1, &del, nil)
        sqlite3_bind_text(del, 1, pageID.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_step(del); sqlite3_finalize(del)

        var ins: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT INTO page_fts(page_id, notebook_id, text) VALUES(?1, ?2, ?3)", -1, &ins, nil)
        sqlite3_bind_text(ins, 1, pageID.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(ins, 2, notebookID.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(ins, 3, text, -1, SQLITE_TRANSIENT)
        sqlite3_step(ins); sqlite3_finalize(ins)

        var up: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO page_text(page_id, notebook_id, text, rects) VALUES(?1, ?2, ?3, ?4)", -1, &up, nil)
        let rectJSON = (try? JSONEncoder().encode(rects.map { [$0.origin.x, $0.origin.y, $0.size.width, $0.size.height] }))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        sqlite3_bind_text(up, 1, pageID.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(up, 2, notebookID.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(up, 3, text, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(up, 4, rectJSON, -1, SQLITE_TRANSIENT)
        sqlite3_step(up); sqlite3_finalize(up)
    }

    func search(_ query: String) -> [Hit] {
        guard let db, !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        var st: OpaquePointer?
        sqlite3_prepare_v2(db, """
            SELECT f.page_id, f.notebook_id,
                   snippet(page_fts, 2, '[', ']', '…', 10)
            FROM page_fts f WHERE page_fts MATCH ?1 LIMIT 100
            """, -1, &st, nil)
        defer { sqlite3_finalize(st) }
        sqlite3_bind_text(st, 1, ftsQuery(query), -1, SQLITE_TRANSIENT)
        var hits: [Hit] = []
        while sqlite3_step(st) == SQLITE_ROW {
            guard let pid = sqlite3_column_text(st, 0), let nid = sqlite3_column_text(st, 1) else { continue }
            let snip = sqlite3_column_text(st, 2).map { String(cString: $0) } ?? ""
            hits.append(Hit(pageID: UUID(uuidString: String(cString: pid)) ?? UUID(),
                            notebookID: UUID(uuidString: String(cString: nid)) ?? UUID(),
                            snippet: snip, rects: []))
        }
        return hits
    }

    /// Stored page text, used to build grounded AI answers with citations.
    func storedText(pageID: UUID) -> String? {
        guard let db else { return nil }
        var st: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT text FROM page_text WHERE page_id = ?1", -1, &st, nil)
        defer { sqlite3_finalize(st) }
        sqlite3_bind_text(st, 1, pageID.uuidString, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(st) == SQLITE_ROW, let c = sqlite3_column_text(st, 0) else { return nil }
        return String(cString: c)
    }

    /// 1-based page position inside its notebook, for citations like [hal 3].
    func pageNumber(pageID: UUID) -> Int {
        guard let db else { return 0 }
        var st: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT notebook_id FROM page_text WHERE page_id = ?1", -1, &st, nil)
        sqlite3_bind_text(st, 1, pageID.uuidString, -1, SQLITE_TRANSIENT)
        var notebook: String?
        if sqlite3_step(st) == SQLITE_ROW, let c = sqlite3_column_text(st, 0) { notebook = String(cString: c) }
        sqlite3_finalize(st)
        guard let nbString = notebook, let nbID = UUID(uuidString: nbString) else { return 0 }
        let pages = NotebookManager().loadPages(for: nbID)
        return (pages.firstIndex { $0.id == pageID } ?? 0) + 1
    }

    /// Quotes each token so punctuation in user input cannot break FTS syntax.
    private func ftsQuery(_ q: String) -> String {
        q.split(separator: " ")
            .map { "\"\($0.replacingOccurrences(of: "\"", with: ""))\"" }
            .joined(separator: " ")
    }

    private static func typedText(in strokes: [InkStroke]) -> String {
        // Text boxes and recognised strokes feed the index; raw ink is OCR'd on demand.
        strokes.compactMap { $0.shape == nil ? nil : nil }.joined()
    }

    /// Recognises handwriting in a page snapshot and links words back to rects.
    func recognizeHandwriting(in image: UIImage, pageID: UUID, notebookID: UUID, completion: @escaping (String) -> Void) {
        guard let cg = image.cgImage else { completion(""); return }
        let request = VNRecognizeTextRequest { [weak self] req, _ in
            var lines: [String] = []
            var rects: [CGRect] = []
            for case let obs as VNRecognizedTextObservation in (req.results ?? []) {
                guard let top = obs.topCandidates(1).first else { continue }
                lines.append(top.string)
                rects.append(obs.boundingBox)
            }
            let text = lines.joined(separator: "\n")
            self?.indexRecognized(pageID: pageID, notebookID: notebookID, text: text,
                                  rects: rects.map { r in
                                      CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height)
                                  })
            DispatchQueue.main.async { completion(text) }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        DispatchQueue.global(qos: .userInitiated).async { try? handler.perform([request]) }
    }
}

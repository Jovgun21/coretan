import Foundation

/// Retrieval over the user's own notes. Deliberately lexical+snippet based:
/// every answer can cite the page it came from, which is what the spec requires
/// ("tampilkan rujukan halaman", "mengizinkan pengguna memeriksa sumber").
struct NoteChunk: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var notebookID: UUID
    var pageID: UUID
    var text: String
    var pageNumber: Int
    var score: Double = 0
}

final class RAGIndex {
    static let shared = RAGIndex()

    /// Pulls candidate chunks for a question from the local full-text index.
    func retrieve(question: String, notebookID: UUID?, limit: Int = 6) -> [NoteChunk] {
        let hits = SearchIndex.shared.search(question)
        var chunks: [NoteChunk] = []
        for h in hits {
            if let nb = notebookID, h.notebookID != nb { continue }
            let text = SearchIndex.shared.storedText(pageID: h.pageID) ?? h.snippet
            guard !text.isEmpty else { continue }
            chunks.append(NoteChunk(notebookID: h.notebookID, pageID: h.pageID,
                                    text: text, pageNumber: SearchIndex.shared.pageNumber(pageID: h.pageID),
                                    score: Self.score(question: question, text: text)))
        }
        return chunks
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    static func score(question: String, text: String) -> Double {
        let terms = Set(question.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
            .subtracting(["yang", "dan", "di", "ke", "dari", "apa", "itu", "ini", "adalah", "the", "a", "is"])
        guard !terms.isEmpty else { return 0 }
        let hay = text.lowercased()
        var hits = 0.0
        for t in terms where hay.contains(t) { hits += 1 }
        return hits / Double(terms.count)
    }

    /// Builds the grounding block handed to the model. Includes page markers so
    /// the model can cite, and an explicit "say you don't know" instruction.
    static func groundingContext(_ chunks: [NoteChunk]) -> String {
        guard !chunks.isEmpty else { return "(tidak ada catatan yang cocok)" }
        return chunks.map { c in
            "[hal \(c.pageNumber)] \(c.text.prefix(1200))"
        }.joined(separator: "\n---\n")
    }
}

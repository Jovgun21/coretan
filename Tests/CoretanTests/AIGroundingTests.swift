import XCTest
@testable import Coretan

final class AIGroundingTests: XCTestCase {

    private func chunks() -> [NoteChunk] {
        [NoteChunk(notebookID: UUID(), pageID: UUID(),
                   text: "Teorema Bayes menghubungkan probabilitas posterior dan prior.",
                   pageNumber: 3),
         NoteChunk(notebookID: UUID(), pageID: UUID(),
                   text: "Distribusi Poisson dipakai untuk kejadian langka.",
                   pageNumber: 7)]
    }

    func testScoresRelevantChunkHigher() {
        let q = "apa itu teorema bayes"
        let a = RAGIndex.score(question: q, text: "Teorema Bayes menghubungkan posterior dan prior.")
        let b = RAGIndex.score(question: q, text: "Distribusi Poisson untuk kejadian langka.")
        XCTAssertGreaterThan(a, b)
        XCTAssertGreaterThan(a, 0)
    }

    func testStopwordsAloneScoreZero() {
        XCTAssertEqual(RAGIndex.score(question: "apa itu yang dan di", text: "apa saja"), 0)
    }

    func testGroundingContextCarriesPageMarkers() {
        let ctx = RAGIndex.groundingContext(chunks())
        XCTAssertTrue(ctx.contains("[hal 3]"))
        XCTAssertTrue(ctx.contains("[hal 7]"))
    }

    func testEmptyContextIsExplicit() {
        let ctx = RAGIndex.groundingContext([])
        XCTAssertTrue(ctx.contains("tidak ada catatan"))
    }

    func testFlashcardParserAcceptsFencedJSON() {
        let raw = """
        Berikut kartunya:
        ```json
        [{"question":"Apa itu Bayes?","answer":"Teorema posterior","category":"konsep","page":3}]
        ```
        """
        let cards = AIAssistant.parseCards(raw, notebookID: nil, chunks: chunks())
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.question, "Apa itu Bayes?")
        XCTAssertEqual(cards.first?.sourcePageID, chunks()[0].pageID, "Card should link back to its source page")
    }

    func testFlashcardParserRejectsGarbage() {
        XCTAssertTrue(AIAssistant.parseCards("tidak ada json di sini", notebookID: nil, chunks: []).isEmpty)
    }
}

import XCTest
@testable import Coretan

final class SpacedRepetitionTests: XCTestCase {

    private func newCard() -> Flashcard {
        Flashcard(question: "q", answer: "a", imageAsset: nil, formula: nil,
                  category: "konsep", sourceNotebookID: nil, sourcePageID: nil)
    }

    func testGoodGradesExpandInterval() {
        var card = newCard()
        SpacedRepetition.apply(.good, to: &card)
        XCTAssertEqual(card.intervalDays, 1, "First successful review schedules tomorrow")
        SpacedRepetition.apply(.good, to: &card)
        XCTAssertEqual(card.intervalDays, 6, "Second schedules six days out")
        let before = card.intervalDays
        SpacedRepetition.apply(.good, to: &card)
        XCTAssertGreaterThan(card.intervalDays, before, "Interval must keep growing")
    }

    func testAgainResetsAndPenalisesEase() {
        var card = newCard()
        SpacedRepetition.apply(.good, to: &card)
        SpacedRepetition.apply(.good, to: &card)
        let easeBefore = card.ease
        SpacedRepetition.apply(.again, to: &card)
        XCTAssertEqual(card.repetitions, 0)
        XCTAssertEqual(card.lapses, 1)
        XCTAssertLessThan(card.ease, easeBefore)
        XCTAssertEqual(card.intervalDays, 0)
    }

    func testEaseIsClamped() {
        var card = newCard()
        for _ in 0..<40 { SpacedRepetition.apply(.again, to: &card) }
        XCTAssertGreaterThanOrEqual(card.ease, 1.3, "Ease may never drop below the floor")
        var other = newCard()
        for _ in 0..<40 { SpacedRepetition.apply(.easy, to: &other) }
        XCTAssertLessThanOrEqual(other.ease, 3.2, "Ease may never exceed the ceiling")
    }

    func testHardKeepsIntervalNonZero() {
        var card = newCard()
        SpacedRepetition.apply(.hard, to: &card)
        XCTAssertGreaterThanOrEqual(card.intervalDays, 1)
        XCTAssertTrue(card.dueDate > Date())
    }

    func testDueFiltersBySchedule() {
        var past = newCard(); past.dueDate = Date().addingTimeInterval(-3600)
        var future = newCard(); future.dueDate = Date().addingTimeInterval(3600)
        let due = SpacedRepetition.due([past, future])
        XCTAssertEqual(due.count, 1)
        XCTAssertEqual(due.first?.id, past.id)
    }
}

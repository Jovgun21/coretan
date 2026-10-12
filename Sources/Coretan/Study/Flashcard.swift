import Foundation

struct Flashcard: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var question: String
    var answer: String
    var imageAsset: String?
    var formula: String?
    var category: String
    var sourceNotebookID: UUID?
    var sourcePageID: UUID?

    // SM-2 scheduling state
    var ease: Double = 2.5
    var intervalDays: Double = 0
    var repetitions: Int = 0
    var dueDate: Date = Date()
    var lapses: Int = 0
}

enum ReviewGrade: Int, CaseIterable {
    case again = 0, hard = 1, good = 2, easy = 3
    var label: String {
        switch self {
        case .again: return "Ulangi"
        case .hard: return "Sulit"
        case .good: return "Lancar"
        case .easy: return "Mudah"
        }
    }
}

/// SM-2 spaced repetition. Cards answered "again" come back the same session;
/// mastered cards get pushed out exponentially.
enum SpacedRepetition {

    static func apply(_ grade: ReviewGrade, to card: inout Flashcard, now: Date = Date()) {
        switch grade {
        case .again:
            card.repetitions = 0
            card.lapses += 1
            card.ease = max(1.3, card.ease - 0.2)
            card.intervalDays = 0
            card.dueDate = now.addingTimeInterval(60 * 10)   // 10 minutes
        case .hard:
            card.ease = max(1.3, card.ease - 0.15)
            card.intervalDays = max(1, card.intervalDays * 1.2)
            card.repetitions += 1
            card.dueDate = now.addingTimeInterval(card.intervalDays * 86400)
        case .good:
            card.repetitions += 1
            if card.repetitions == 1 { card.intervalDays = 1 }
            else if card.repetitions == 2 { card.intervalDays = 6 }
            else { card.intervalDays = (card.intervalDays * card.ease).rounded() }
            card.dueDate = now.addingTimeInterval(card.intervalDays * 86400)
        case .easy:
            card.ease = min(3.2, card.ease + 0.15)
            card.repetitions += 1
            card.intervalDays = max(4, (card.intervalDays * card.ease).rounded())
            card.dueDate = now.addingTimeInterval(card.intervalDays * 86400)
        }
    }

    static func due(_ cards: [Flashcard], now: Date = Date()) -> [Flashcard] {
        cards.filter { $0.dueDate <= now }.sorted { $0.dueDate < $1.dueDate }
    }
}

final class StudyStore: ObservableObject {
    static let shared = StudyStore()
    @Published private(set) var cards: [Flashcard] = []
    private let key = "coretan.flashcards"

    init() { load() }

    func load() {
        guard let d = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([Flashcard].self, from: d) else { return }
        cards = list
    }

    func save() {
        if let d = try? JSONEncoder().encode(cards) { UserDefaults.standard.set(d, forKey: key) }
    }

    func add(_ card: Flashcard) { cards.append(card); save() }
    func add(_ list: [Flashcard]) { cards.append(contentsOf: list); save() }
    func update(_ card: Flashcard) {
        if let i = cards.firstIndex(where: { $0.id == card.id }) { cards[i] = card; save() }
    }
    func remove(_ id: UUID) { cards.removeAll { $0.id == id }; save() }
    var dueToday: [Flashcard] { SpacedRepetition.due(cards) }
}
